#!/bin/bash
# User Data Script for dev-project-jen-k8-min instance initialization

# Set variables
LOG_FILE="/var/log/user-data.log"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

log "Starting dev-project-jen-k8-min instance initialization..."

# Update system packages
log "Updating system packages..."
yum update -y

# Install essential packages
log "Installing essential packages..."
yum install -y wget curl git unzip htop

# Set timezone
timedatectl set-timezone UTC

# Create welcome message
cat > /etc/motd << 'EOF'

=======================================================
   Welcome to dev-project-jen-k8-min EC2 Instance
=======================================================

This instance is configured with:
- Amazon Linux 2023 (kernel 6.1)
- Instance Type: t2.medium 
- Storage: 40GB

Services will be installed via Terraform provisioners:
- Docker & Docker Compose
- Jenkins (port 8080)
- SonarQube (port 9000) 
- Kubernetes via Minikube

Check /home/ec2-user/service_info.txt for service details
after the provisioning completes.

=======================================================
EOF

log "Instance initialization completed. Ready for service installation via Terraform provisioners."
