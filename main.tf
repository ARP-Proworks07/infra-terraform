# Terraform configuration for dev-project-jen-k8-min EC2 instance

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
  region = "us-east-1"  # Default region, adjust as needed
}

# Data source for Amazon Linux 2023 kernel 6.1 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-6.1-x86_64"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get existing security group by name
data "aws_security_group" "existing_sg" {
  name = "launch-wizard-6"
}

# Create key pair for EC2 instance access
resource "aws_key_pair" "dev_project_key" {
  key_name   = var.key_name
  public_key = file(var.public_key_path)

  tags = {
    Name = var.key_name
  }
}

# EC2 Instance - dev-project-jen-k8-min
resource "aws_instance" "dev_project_instance" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t2.medium"
  key_name              = aws_key_pair.dev_project_key.key_name
  vpc_security_group_ids = [data.aws_security_group.existing_sg.id]
  
  # Ensure we get a public IP
  associate_public_ip_address = true
  
  # User data script to install and configure services
  user_data = file("user_data.sh")

  # Storage configuration - 40GB as requested
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 40
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name = "dev-project-jen-k8-min"
  }

  # Install Docker and verify it's working
  provisioner "remote-exec" {
    inline = [
      "#!/bin/bash",
      "# Wait for system to be ready",
      "sleep 60",
      "",
      "# Update system",
      "sudo yum update -y",
      "",
      "# Install Docker",
      "sudo yum install -y docker",
      "sudo systemctl start docker",
      "sudo systemctl enable docker",
      "sudo usermod -a -G docker ec2-user",
      "",
      "# Verify Docker installation",
      "sudo docker --version",
      "sudo systemctl is-active docker",
      "",
      "# Install Docker Compose",
      "sudo curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)\" -o /usr/local/bin/docker-compose",
      "sudo chmod +x /usr/local/bin/docker-compose"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file(var.private_key_path)
      host        = self.public_ip
      timeout     = "10m"
    }
  }

  # Install Jenkins and verify it's working
  provisioner "remote-exec" {
    inline = [
      "#!/bin/bash",
      "",
      "# Install Java (required for Jenkins)",
      "sudo yum install -y java-17-amazon-corretto-devel",
      "",
      "# Install Jenkins",
      "sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo",
      "sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key",
      "sudo yum install -y jenkins",
      "",
      "# Start and enable Jenkins",
      "sudo systemctl start jenkins",
      "sudo systemctl enable jenkins",
      "",
      "# Wait for Jenkins to start",
      "sleep 30",
      "",
      "# Verify Jenkins installation",
      "sudo systemctl is-active jenkins",
      "",
      "# Get initial admin password",
      "sudo cat /var/lib/jenkins/secrets/initialAdminPassword > /home/ec2-user/jenkins_initial_password.txt",
      "sudo chown ec2-user:ec2-user /home/ec2-user/jenkins_initial_password.txt"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file(var.private_key_path)
      host        = self.public_ip
      timeout     = "15m"
    }
  }

  # Install SonarQube and verify it's working
  provisioner "remote-exec" {
    inline = [
      "#!/bin/bash",
      "",
      "# Create sonarqube user",
      "sudo useradd -r -s /bin/false sonarqube",
      "",
      "# Install SonarQube",
      "cd /tmp",
      "sudo wget https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-9.9.3.79811.zip",
      "sudo unzip sonarqube-9.9.3.79811.zip",
      "sudo mv sonarqube-9.9.3.79811 /opt/sonarqube",
      "sudo chown -R sonarqube:sonarqube /opt/sonarqube",
      "",
      "# Configure system limits for SonarQube",
      "echo 'vm.max_map_count=524288' | sudo tee -a /etc/sysctl.conf",
      "echo 'fs.file-max=131072' | sudo tee -a /etc/sysctl.conf",
      "sudo sysctl -p",
      "",
      "# Create SonarQube systemd service",
      "sudo tee /etc/systemd/system/sonarqube.service > /dev/null << 'EOF'",
      "[Unit]",
      "Description=SonarQube service",
      "After=syslog.target network.target",
      "",
      "[Service]",
      "Type=forking",
      "ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start",
      "ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop",
      "User=sonarqube",
      "Group=sonarqube",
      "Restart=always",
      "LimitNOFILE=65536",
      "LimitNPROC=4096",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "EOF",
      "",
      "# Start and enable SonarQube",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable sonarqube",
      "sudo systemctl start sonarqube",
      "",
      "# Wait for SonarQube to start",
      "sleep 45",
      "",
      "# Verify SonarQube installation",
      "sudo systemctl is-active sonarqube"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file(var.private_key_path)
      host        = self.public_ip
      timeout     = "20m"
    }
  }

  # Install Kubernetes via Minikube and verify it's working
  provisioner "remote-exec" {
    inline = [
      "#!/bin/bash",
      "",
      "# Install kubectl",
      "curl -LO \"https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\"",
      "sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl",
      "",
      "# Install Minikube",
      "curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64",
      "sudo install minikube /usr/local/bin/",
      "",
      "# Configure Minikube to use Docker driver",
      "minikube config set driver docker",
      "",
      "# Start Minikube cluster",
      "minikube start --driver=docker --cpus=2 --memory=2048 --disk-size=10g",
      "",
      "# Enable dashboard and ingress addons",
      "minikube addons enable dashboard",
      "minikube addons enable ingress",
      "",
      "# Verify Kubernetes installation",
      "kubectl cluster-info",
      "kubectl get nodes",
      "",
      "# Create alias for easier kubectl usage",
      "echo 'alias k=kubectl' >> ~/.bashrc",
      "",
      "# Create a simple test deployment to verify Kubernetes is working",
      "kubectl create deployment hello-minikube --image=nginx:latest",
      "kubectl expose deployment hello-minikube --type=NodePort --port=80",
      "",
      "# Verify the deployment",
      "sleep 30",
      "kubectl get pods",
      "kubectl get services"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file(var.private_key_path)
      host        = self.public_ip
      timeout     = "25m"
    }
  }

  # Create service information file
  provisioner "remote-exec" {
    inline = [
      "#!/bin/bash",
      "",
      "# Create service information file",
      "cat > /home/ec2-user/service_info.txt << 'EOF'",
      "=== dev-project-jen-k8-min Service Information ===",
      "",
      "Instance Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)",
      "",
      "Service URLs:",
      "- Jenkins: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080",
      "- SonarQube: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9000",
      "",
      "Default Credentials:",
      "- SonarQube: admin/admin (change after first login)",
      "- Jenkins: admin/[check jenkins_initial_password.txt]",
      "",
      "Service Status Commands:",
      "- Docker: sudo systemctl status docker",
      "- Jenkins: sudo systemctl status jenkins", 
      "- SonarQube: sudo systemctl status sonarqube",
      "- Kubernetes: kubectl get nodes",
      "- Minikube: minikube status",
      "",
      "Useful Commands:",
      "- Access Minikube dashboard: minikube dashboard --url",
      "- View all pods: kubectl get pods -A",
      "- View Jenkins logs: sudo journalctl -u jenkins -f",
      "- View SonarQube logs: sudo journalctl -u sonarqube -f",
      "",
      "Installation completed at: $(date)",
      "EOF",
      "",
      "echo 'All services have been installed and configured successfully!'",
      "echo 'Check /home/ec2-user/service_info.txt for detailed information.'"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file(var.private_key_path)
      host        = self.public_ip
      timeout     = "5m"
    }
  }
}

