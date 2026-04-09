terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

# --- DYNAMIC DISCOVERY DATA SOURCES ---

# Automatically find YOUR default VPC
data "aws_vpc" "default" {
  default = true
}

# Automatically find a default subnet in your VPC
data "aws_subnets" "all_default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Select the first subnet found in your account
data "aws_subnet" "selected" {
  id = data.aws_subnets.all_default.ids[0]
}

# Discover your AMI in your own account
# Discover the official Ubuntu 22.04 AMI
data "aws_ami" "hc-security-base" {
  most_recent = true
  owners      = ["099720109477"] # This is the official AWS Account ID for Canonical (Ubuntu)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_iam_policy" "security_compute_access" {
  name = "SecurityComputeAccess"
}

data "aws_iam_policy_document" "allow_ec2" {
  statement {
    sid     = "AllowEC2"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Insecure Security Group

resource "aws_security_group" "insecure" {
  name   = "insecure-sg"
  vpc_id = data.aws_vpc.default.id # Dynamically linked

  ingress {
    description = "Open SSH to the world"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Open all ports to the world"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Insecure IAM

resource "aws_iam_policy" "insecure_policy" {
  name        = "InsecureWildcardPolicy"
  description = "Allows all actions on all resources (INTENTIONALLY BAD)"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = "*",
      Resource = "*"
    }]
  })
}

resource "aws_iam_role" "basic_ec2" {
  name               = "vulnerability-demo"
  assume_role_policy = data.aws_iam_policy_document.allow_ec2.json
  managed_policy_arns = [
    data.aws_iam_policy.security_compute_access.arn
  ]
}

resource "aws_iam_role_policy_attachment" "attach_insecure" {
  role       = aws_iam_role.basic_ec2.name
  policy_arn = aws_iam_policy.insecure_policy.arn
}

resource "aws_iam_instance_profile" "basic_ec2" {
  name = "vulnerability-demo"
  role = aws_iam_role.basic_ec2.name
}

# EC2 Instance (vulnerable)

resource "aws_instance" "basic" {
  ami                  = data.aws_ami.hc-security-base.id
  iam_instance_profile = aws_iam_instance_profile.basic_ec2.name
  instance_type        = "m6i.xlarge"
  subnet_id            = data.aws_subnet.selected.id

  # INSECURE SG
  vpc_security_group_ids = [aws_security_group.insecure.id]

  # UNENCRYPTED ROOT DISK (Wiz will flag)
  root_block_device {
    encrypted    = false
    volume_size  = 50
  }

  # IMDSv1 ENABLED (Wiz will flag)
  metadata_options {
    http_tokens = "optional"
  }

  tags = {
    hc-config-as-code = "terraform"
    Name              = "insecure-demo-vm"
  }
}
