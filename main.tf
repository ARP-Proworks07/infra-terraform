# Terraform configuration for provisioning Jenkins, SonarQube, and Minikube on AWS EC2 (t2.medium)

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = "us-east-1"
}

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

#security group 
resource "aws_security_group" "devops_ec2_sg" {
  name_prefix = "devops-services-amazon_clone"
  description = "Security group for HTTP, HTTPS, SSH, Jenkins, SonarQube, and Minikube"
  vpc_id      = data.aws_vpc.default.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }

  # HTTP access
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  # HTTPS access
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  # Jenkins default port
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Jenkins"
  }

  # SonarQube default port
  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SonarQube"
  }

  # k3s default port
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Kubernetes API"
  }

  # Amazon Clone Frontend (React/Vite)
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Amazon Clone Frontend"
  }

  # Amazon Clone Backend (Node.js/Express)
  ingress {
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Amazon Clone Backend API"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name        = "devops-servers-sg"
  }
}

# EC2 Instance for Jenkins, SonarQube, and Amazon Clone
resource "aws_instance" "devops_server" {
  ami                    = "ami-0fc5d935ebf8bc3bc" # Ubuntu 22.04 us-east-1
  instance_type          = "t2.medium"
  key_name              = var.key_name
  vpc_security_group_ids = [aws_security_group.devops_ec2_sg.id]
  
  # Auto-assign public IP for external access
  associate_public_ip_address = true
  
  # Bootstrap script that installs Jenkins, SonarQube, K3s, and deploys amazon-clone
  # This runs automatically when the EC2 instance starts for the first time
  user_data = file("${path.module}/user_data.sh")
  
  # Force user_data script to run on every instance replacement/restart
  user_data_replace_on_change = true

  # Increase root volume size for all the services and applications
  root_block_device {
    volume_size           = 50      # 50 GB disk (required for Jenkins, SonarQube, K3s, and Amazon Clone)
    volume_type           = "gp3"   # General Purpose SSD (faster performance)
    delete_on_termination = true   # Clean up storage when instance is terminated
    encrypted             = true   # Encrypt storage for security
  }

  # Instance metadata options for security
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"  # Require IMDSv2 for security
    http_put_response_hop_limit = 1
  }

  tags = {
    Name        = "Dev-Server-Jenkins-SonarQube-K3s-amazon_clone"
    Environment = "Development"
    Project     = "Amazon-Clone-DevOps"
    ManagedBy   = "Terraform"
    Purpose     = "CI/CD Pipeline with Jenkins, SonarQube, K3s, and Amazon Clone App"
  }
}