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

# Configure the AWS Provider
provider "aws" {
  region = var.region
}

# Data source for the latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get default subnet
data "aws_subnet" "default" {
  vpc_id            = data.aws_vpc.default.id
  availability_zone = "${var.region}a"
  default_for_az    = true
}

# Create security group for Jenkins, SonarQube, and Minikube
resource "aws_security_group" "devops_sg" {
  name_prefix = "devops-services-"
  description = "Security group for Jenkins, SonarQube, and Minikube"
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

  # Kubernetes API server (for Minikube)
  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Kubernetes API Server"
  }

  # Kubernetes Dashboard
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Kubernetes NodePort services"
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
    Name        = "devops-services-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Create key pair for EC2 instance access
resource "aws_key_pair" "devops_key" {
  key_name   = var.key_name
  public_key = var.public_key_content

  tags = {
    Name        = var.key_name
    Environment = var.environment
    Project     = var.project_name
  }
}

# EC2 Instance for Jenkins, SonarQube, and Minikube
resource "aws_instance" "devops_server" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.instance_type
  key_name              = aws_key_pair.devops_key.key_name
  vpc_security_group_ids = [aws_security_group.devops_sg.id]
  subnet_id             = data.aws_subnet.default.id
  
  # Ensure we get a public IP
  associate_public_ip_address = true
  
  # User data script to install and configure services
  user_data = file("user_data.sh")

  # Storage configuration
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = true
    
    tags = {
      Name        = "${var.project_name}-root-volume"
      Environment = var.environment
    }
  }

  tags = {
    Name        = "${var.project_name}-devops-server"
    Environment = var.environment
    Project     = var.project_name
    Services    = "Jenkins,SonarQube,Minikube"
  }

  # Wait for the instance to be ready
  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for services to start...'",
      "sleep 30"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = var.private_key_content
      host        = self.public_ip
      timeout     = "10m"
    }
  }
}

