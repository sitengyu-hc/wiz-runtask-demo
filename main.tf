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

#-----no data source used due to explicit deny on describe and list actions---#


# Insecure Security Group

resource "aws_security_group" "insecure" {
  name   = "insecure-sg"
  vpc_id = "vpc-0453a7f647b768fc0"

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
}

resource "aws_iam_role_policy_attachment" "attach_insecure" {
  role       = aws_iam_role.basic_ec2.name
  policy_arn = "arn:aws:iam::856558476393:policy/SecurityComputeAccess" # Use the FULL ARN
}

resource "aws_iam_instance_profile" "basic_ec2" {
  name = "vulnerability-demo"
  role = aws_iam_role.basic_ec2.name
}

# EC2 Instance (vulnerable)

resource "aws_instance" "basic" {
  ami                  = "ami-002c8fb8b59607dfb"
  iam_instance_profile = aws_iam_instance_profile.basic_ec2.name
  instance_type        = "m6i.xlarge"
  subnet_id            = "subnet-03c9e27b4070e3385"

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
