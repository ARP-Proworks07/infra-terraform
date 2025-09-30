#!/bin/bash
# User Data Script for installing Jenkins, SonarQube, and Minikube on Amazon Linux 2

# Set variables
LOG_FILE="/var/log/user-data.log"
JENKINS_HOME="/var/lib/jenkins"
SONAR_HOME="/opt/sonarqube"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

log "Starting DevOps infrastructure setup..."

# Update system
log "Updating system packages..."
yum update -y

# Install essential packages
log "Installing essential packages..."
yum install -y wget curl git unzip docker java-11-openjdk-devel

# Configure Java environment
log "Configuring Java environment..."
echo 'export JAVA_HOME=/usr/lib/jvm/java-11-openjdk' >> /etc/environment
echo 'export PATH=$PATH:$JAVA_HOME/bin' >> /etc/environment
source /etc/environment

# Start and enable Docker
log "Starting Docker service..."
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# Install Docker Compose
log "Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install Jenkins
log "Installing Jenkins..."
wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io.key
yum install -y jenkins

# Configure Jenkins
log "Configuring Jenkins..."
systemctl start jenkins
systemctl enable jenkins

# Wait for Jenkins to start and get initial admin password
sleep 30
if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
    JENKINS_INITIAL_PASSWORD=$(cat /var/lib/jenkins/secrets/initialAdminPassword)
    log "Jenkins initial admin password: $JENKINS_INITIAL_PASSWORD"
    echo "Jenkins initial admin password: $JENKINS_INITIAL_PASSWORD" > /home/ec2-user/jenkins_password.txt
    chown ec2-user:ec2-user /home/ec2-user/jenkins_password.txt
fi

# Install SonarQube
log "Installing SonarQube..."

# Create sonarqube user
useradd -r -s /bin/false sonarqube

# Download and install SonarQube
cd /opt
wget https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-9.9.2.77730.zip
unzip sonarqube-9.9.2.77730.zip
mv sonarqube-9.9.2.77730 sonarqube
chown -R sonarqube:sonarqube sonarqube
rm -f sonarqube-9.9.2.77730.zip

# Configure SonarQube system limits
echo 'vm.max_map_count=524288' >> /etc/sysctl.conf
echo 'fs.file-max=131072' >> /etc/sysctl.conf
sysctl -p

echo 'sonarqube   -   nofile   131072' >> /etc/security/limits.conf
echo 'sonarqube   -   nproc    8192' >> /etc/security/limits.conf

# Create SonarQube systemd service
cat > /etc/systemd/system/sonarqube.service << EOF
[Unit]
Description=SonarQube service
After=syslog.target network.target

[Service]
Type=notify
ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start
ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop
User=sonarqube
Group=sonarqube
Restart=always
LimitNOFILE=131072
LimitNPROC=8192

[Install]
WantedBy=multi-user.target
EOF

# Start SonarQube
log "Starting SonarQube..."
systemctl daemon-reload
systemctl enable sonarqube
systemctl start sonarqube

# Install kubectl
log "Installing kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Install Minikube
log "Installing Minikube..."
curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
chmod +x minikube
mv minikube /usr/local/bin/

# Configure Minikube for ec2-user
log "Configuring Minikube..."
su - ec2-user << 'EOF'
# Start Minikube with Docker driver
minikube config set driver docker
minikube start --driver=docker --cpus=2 --memory=2048

# Enable dashboard and ingress addons
minikube addons enable dashboard
minikube addons enable ingress

# Create alias for kubectl
echo 'alias kubectl="minikube kubectl --"' >> ~/.bashrc
source ~/.bashrc

log "Minikube setup completed for ec2-user"
EOF

# Install additional tools
log "Installing additional DevOps tools..."

# Install Maven
cd /opt
wget https://archive.apache.org/dist/maven/maven-3/3.8.6/binaries/apache-maven-3.8.6-bin.tar.gz
tar xzf apache-maven-3.8.6-bin.tar.gz
mv apache-maven-3.8.6 maven
rm -f apache-maven-3.8.6-bin.tar.gz
echo 'export M2_HOME=/opt/maven' >> /etc/environment
echo 'export PATH=$PATH:$M2_HOME/bin' >> /etc/environment

# Install Gradle
cd /opt
wget https://services.gradle.org/distributions/gradle-7.6-bin.zip
unzip gradle-7.6-bin.zip
mv gradle-7.6 gradle
rm -f gradle-7.6-bin.zip
echo 'export GRADLE_HOME=/opt/gradle' >> /etc/environment
echo 'export PATH=$PATH:$GRADLE_HOME/bin' >> /etc/environment

# Create a welcome message with service URLs
cat > /etc/motd << EOF

=================================================
DevOps Infrastructure Setup Complete!
=================================================

Services running on this instance:

🚀 Jenkins:    http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080
   Initial admin password location: /home/ec2-user/jenkins_password.txt

📊 SonarQube:  http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9000
   Default credentials: admin/admin

⚡ Minikube:   Use 'minikube dashboard' to start the dashboard
   Kubectl:    Use 'minikube kubectl --' or set up alias

🔧 Additional Tools Installed:
   - Docker & Docker Compose
   - Maven (/opt/maven)
   - Gradle (/opt/gradle)
   - Git

📝 Useful Commands:
   - Check service status: sudo systemctl status jenkins sonarqube docker
   - View Jenkins logs: sudo journalctl -u jenkins -f
   - View SonarQube logs: sudo journalctl -u sonarqube -f
   - Access Minikube: sudo su - ec2-user, then minikube status

=================================================
EOF

# Set proper permissions and create info file
chown ec2-user:ec2-user /home/ec2-user/jenkins_password.txt 2>/dev/null || true

# Create service info file
cat > /home/ec2-user/service-info.txt << EOF
DevOps Infrastructure Service Information
========================================

Instance Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

Service URLs:
- Jenkins: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080
- SonarQube: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9000

Default Credentials:
- SonarQube: admin/admin (change after first login)

Jenkins Initial Password:
$(cat /home/ec2-user/jenkins_password.txt 2>/dev/null || echo "Check /var/lib/jenkins/secrets/initialAdminPassword")

Commands:
- Check all services: sudo systemctl status jenkins sonarqube docker
- Minikube status: minikube status
- Minikube dashboard: minikube dashboard --url
- Access Minikube kubectl: minikube kubectl -- get pods -A

Installation completed at: $(date)
EOF

chown ec2-user:ec2-user /home/ec2-user/service-info.txt

log "DevOps infrastructure setup completed successfully!"

# Final service status check
sleep 60
log "Final service status check:"
systemctl is-active jenkins | tee -a $LOG_FILE
systemctl is-active sonarqube | tee -a $LOG_FILE
systemctl is-active docker | tee -a $LOG_FILE

log "Setup script finished. Check /home/ec2-user/service-info.txt for service details."
