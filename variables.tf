# Variables for AWS infrastructure configuration

variable "key_name" {
  description = "Name for the EC2 key pair"
  type        = string
  default     = "aditya23july2025"
}

variable "private_key_path" {
  description = "Path to the private key file"
  type        = string
  default     = "~/.ssh/aditya23july2025.pem"
}

variable "public_key_path" {
  description = "Path to the public key file" 
  type        = string
  default     = "~/.ssh/aditya23july2025.pub"
}
