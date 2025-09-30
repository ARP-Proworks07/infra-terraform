# Variables for AWS infrastructure configuration

variable "region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "devops-infrastructure"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.medium"
  
  validation {
    condition     = can(regex("^t2\\.(medium|large|xlarge)$|^t3\\.(medium|large|xlarge)$|^m5\\.(large|xlarge)$", var.instance_type))
    error_message = "Instance type must be at least t2.medium for running Jenkins, SonarQube, and Minikube."
  }
}

variable "key_name" {
  description = "Name for the EC2 key pair"
  type        = string
  default     = "devops-infrastructure-key"
}

variable "public_key_content" {
  description = "Content of the public key for EC2 access (ssh-rsa AAAAB3... format)"
  type        = string
}

variable "private_key_content" {
  description = "Content of the private key for provisioning (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "root_volume_size" {
  description = "Size of the root EBS volume in GB"
  type        = number
  default     = 30
  
  validation {
    condition     = var.root_volume_size >= 20
    error_message = "Root volume size must be at least 20GB."
  }
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the services"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
