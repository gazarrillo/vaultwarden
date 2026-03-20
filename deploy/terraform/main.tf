terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# --- Variables ---

variable "aws_region" {
  default = "us-east-2"
}

variable "domain" {
  description = "Your vaultwarden domain (e.g. vault.yourdomain.com)"
  type        = string
}

variable "key_name" {
  description = "Name of your existing EC2 key pair for SSH access"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "Your office/home IP for SSH access"
  type        = string
  default     = "0.0.0.0/0" # Restrict this to your IP in production
}

# --- Networking ---

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --- Security Group ---

resource "aws_security_group" "vaultwarden" {
  name        = "vaultwarden"
  description = "Allow HTTP, HTTPS, and SSH"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- EC2 Instance ---

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_instance" "vaultwarden" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.vaultwarden.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y docker.io docker-compose-v2
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ubuntu

    mkdir -p /data/vaultwarden
  EOF

  tags = {
    Name = "vaultwarden"
  }
}

resource "aws_eip" "vaultwarden" {
  instance = aws_instance.vaultwarden.id
  domain   = "vpc"
}

# --- Outputs ---

output "public_ip" {
  value       = aws_eip.vaultwarden.public_ip
  description = "Point your domain's A record to this IP"
}

output "ssh_command" {
  value = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_eip.vaultwarden.public_ip}"
}
