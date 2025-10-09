#!/bin/bash
exec > /var/log/userdata.log 2>&1
set -xe

echo "[INFO] ======== Starting EC2 Bootstrap ========="
echo "[INFO] Bootstrap started at: $(date)"

# --- Wait for apt locks and system readiness ---
echo "[INFO] Waiting for system readiness..."
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /varecho "[INFO] Amazon Clone application deployment completed!"

# -------------------------------
# Final Status Check and Summary
# -------------------------------
echo "[INFO] Performing final status check..."
sleep 10

echo "[INFO] ======== DEPLOYMENT STATUS ========"
echo "Docker containers:"
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "Services accessibility test:"
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "localhost")

# Test each service
for service in "8080:Jenkins" "9000:SonarQube" "3000:Frontend" "3001:Backend"; do
    port=$(echo $service | cut -d: -f1)
    name=$(echo $service | cut -d: -f2)
    
    if curl -s --connect-timeout 5 http://localhost:$port >/dev/null 2>&1; then
        echo "✅ $name (port $port): RUNNING"
    else
        echo "❌ $name (port $port): NOT ACCESSIBLE"
    fi
done

echo ""
echo "Kubernetes status:"
sudo kubectl get nodes --no-headers 2>/dev/null || echo "K3s not ready"
sudo kubectl get pods -A --no-headers 2>/dev/null | wc -l | xargs echo "Total pods running:" || echo "No pods yet"

echo ""
echo "[INFO] ======== ACCESS INFORMATION ========"
JENKINS_PASSWORD=$(sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || echo "Check container logs")
echo "Public IP: $PUBLIC_IP"
echo "Jenkins: http://$PUBLIC_IP:8080 (admin/$JENKINS_PASSWORD)"
echo "SonarQube: http://$PUBLIC_IP:9000 (admin/admin)"
echo "Amazon Clone: http://$PUBLIC_IP:3000"
echo "Backend API: http://$PUBLIC_IP:3001"
echo ""
echo "SSH Access: ssh -i ~/.ssh/your-key.pem ubuntu@$PUBLIC_IP"
echo ""

# Create a status file for easy checking
cat > /home/ubuntu/deployment-status.txt <<EOF
Deployment completed at: $(date)
Public IP: $PUBLIC_IP
Jenkins Password: $JENKINS_PASSWORD

Service URLs:
- Jenkins: http://$PUBLIC_IP:8080
- SonarQube: http://$PUBLIC_IP:9000
- Frontend: http://$PUBLIC_IP:3000  
- Backend: http://$PUBLIC_IP:3001

To check logs:
- sudo docker logs jenkins
- sudo docker logs sonarqube
- sudo docker compose -f /home/ubuntu/amazon-clone/docker-compose.prod.yml logs

All Docker containers should be running. Use 'sudo docker ps' to verify.
EOF

chown ubuntu:ubuntu /home/ubuntu/deployment-status.txt

# -------------------------------
# Reboot if required
# -------------------------------
if [ -f /var/run/reboot-required ]; then
    echo "[INFO] System reboot required. Rebooting..."
    sudo reboot
fi

echo "[INFO] ======== Bootstrap Completed Successfully ========"
echo "[INFO] Deployment completed at: $(date)"
echo "[INFO] Status summary saved to: /home/ubuntu/deployment-status.txt"ock >/dev/null 2>&1; do
     echo "Waiting for apt lock..."
     sleep 10
done

# Wait for cloud-init to finish
while [ ! -f /var/lib/cloud/instance/boot-finished ]; do
    echo "Waiting for cloud-init to finish..."
    sleep 10
done

# Ensure we have network connectivity
echo "[INFO] Testing network connectivity..."
until curl -s --connect-timeout 10 https://google.com > /dev/null; do
    echo "Waiting for network connectivity..."
    sleep 10
done

# -------------------------------
# System Update & Tools
# -------------------------------
echo "[INFO] Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y
sudo apt-get upgrade -y

echo "[INFO] Installing required packages..."
sudo apt-get install -y \
        docker.io git curl wget unzip openjdk-17-jdk apt-transport-https \
        ca-certificates gnupg lsb-release software-properties-common fontconfig \
        conntrack jq docker-compose-plugin net-tools htop tree

# Enable Docker and add ubuntu user to group
echo "[INFO] Setting up Docker..."
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ubuntu
sudo chmod 666 /var/run/docker.sock

# Wait for Docker to be ready
echo "[INFO] Waiting for Docker to be ready..."
until sudo docker info >/dev/null 2>&1; do
    echo "Waiting for Docker daemon..."
    sleep 5
done
echo "[INFO] Docker is ready!"

# -------------------------------
# Install K3s (Single Node)
# -------------------------------
echo "[INFO] Installing K3s..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --write-kubeconfig-mode 644" sh -

# Wait for K3s to be ready
echo "[INFO] Waiting for K3s to be ready..."
until sudo k3s kubectl get nodes --no-headers | grep -q "Ready"; do
    echo "Waiting for K3s node to be ready..."
    sleep 10
done

# Configure kubeconfig for ubuntu user
echo "[INFO] Configuring kubectl for ubuntu user..."
mkdir -p /home/ubuntu/.kube
sudo cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
sudo chown ubuntu:ubuntu /home/ubuntu/.kube/config
chmod 600 /home/ubuntu/.kube/config

# Install kubectl for easier access
echo "[INFO] Installing kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

echo "[INFO] K3s installation completed!"

# -------------------------------
# Fix containerd socket permissions for Jenkins
# -------------------------------
sudo groupadd -f containerd
sudo chown root:containerd /run/k3s/containerd/containerd.sock || true
sudo chmod 660 /run/k3s/containerd/containerd.sock || true

# -------------------------------
# Ensure ctr wrapper exists (for Jenkins)
# -------------------------------
sudo tee /usr/local/bin/ctr > /dev/null <<'CTR_EOF'
#!/bin/bash
exec /usr/local/bin/k3s ctr "$@"
CTR_EOF
sudo chmod +x /usr/local/bin/ctr

# -------------------------------
# Install kubectl (CLI tool for Jenkins)
# -------------------------------
sudo snap install kubectl --classic || true

# -------------------------------
# Get group IDs for proper container mapping
# -------------------------------
# Ensure groups exist before getting IDs
sudo groupadd -f docker      # -f flag means "don't fail if group exists"
sudo groupadd -f containerd

DOCKER_GID=$(getent group docker | cut -d: -f3)
CONTAINERD_GID=$(getent group containerd | cut -d: -f3)

echo "[INFO] Docker GID: $DOCKER_GID, Containerd GID: $CONTAINERD_GID"

# -------------------------------
# Run Jenkins container (with access to Docker & K3s)
# -------------------------------
echo "[INFO] Starting Jenkins container..."

# Remove any existing Jenkins container
sudo docker rm -f jenkins >/dev/null 2>&1 || true

# Create Jenkins volume if it doesn't exist
sudo docker volume create jenkins_home >/dev/null 2>&1 || true

# Start Jenkins with proper configuration
sudo docker run -d --name jenkins --restart unless-stopped \
    -p 8080:8080 -p 50000:50000 \
    -v jenkins_home:/var/jenkins_home \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /usr/bin/docker:/usr/bin/docker \
    -v /usr/local/bin/kubectl:/usr/local/bin/kubectl \
    -v /usr/local/bin/k3s:/usr/local/bin/k3s \
    -v /etc/rancher/k3s/k3s.yaml:/var/jenkins_home/.kube/config \
    --group-add $DOCKER_GID \
    --group-add $CONTAINERD_GID \
    -e JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
    jenkins/jenkins:lts-jdk17

# Wait for Jenkins to start
echo "[INFO] Waiting for Jenkins to start..."
until curl -s http://localhost:8080/login >/dev/null; do
    echo "Waiting for Jenkins..."
    sleep 10
done

# Fix Jenkins permissions after it's running
sleep 10
sudo docker exec -u root jenkins bash -c "
    groupadd -f docker
    usermod -aG docker jenkins
    chown -R jenkins:jenkins /var/jenkins_home/.kube
    chmod 644 /var/jenkins_home/.kube/config
" >/dev/null 2>&1 || true

echo "[INFO] Jenkins started successfully!"

# -------------------------------
# Run SonarQube container
# -------------------------------
echo "[INFO] Starting SonarQube container..."

# Remove any existing SonarQube container
sudo docker rm -f sonarqube >/dev/null 2>&1 || true

# Create SonarQube volumes
sudo docker volume create sonarqube_data >/dev/null 2>&1 || true
sudo docker volume create sonarqube_extensions >/dev/null 2>&1 || true
sudo docker volume create sonarqube_logs >/dev/null 2>&1 || true

# Configure system settings for SonarQube
sudo sysctl -w vm.max_map_count=524288
sudo sysctl -w fs.file-max=131072
echo 'vm.max_map_count=524288' | sudo tee -a /etc/sysctl.conf
echo 'fs.file-max=131072' | sudo tee -a /etc/sysctl.conf

# Start SonarQube
sudo docker run -d --name sonarqube --restart unless-stopped \
    -p 9000:9000 \
    -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
    -v sonarqube_data:/opt/sonarqube/data \
    -v sonarqube_extensions:/opt/sonarqube/extensions \
    -v sonarqube_logs:/opt/sonarqube/logs \
    sonarqube:lts-community

echo "[INFO] SonarQube container started!"

# -------------------------------
# Fix Jenkins permissions after boot
# -------------------------------
sleep 20
sudo docker exec -u root jenkins bash -c "groupadd -f docker && usermod -aG docker jenkins" || true
sudo docker exec -u root jenkins bash -c "usermod -aG containerd jenkins || true" || true
sudo docker run --rm -v jenkins_home:/var/jenkins_home alpine sh -c "chown -R 1000:1000 /var/jenkins_home" || true

# Apply all runtime permission fixes
sudo chmod 666 /var/run/docker.sock || true
sudo chmod 666 /run/k3s/containerd/containerd.sock || true

# Restart Jenkins to apply group changes
sudo docker restart jenkins || true

# Optional: verify containerd connectivity (debug only)
sudo docker exec -it jenkins ctr --address /run/k3s/containerd/containerd.sock version || true

# -------------------------------
# Wait for SonarQube to become ready
# -------------------------------
echo "[INFO] Waiting for SonarQube to be ready..."
SONAR_ATTEMPTS=0
until curl -s http://localhost:9000/api/system/status | grep -q '"status":"UP"' || [ $SONAR_ATTEMPTS -gt 30 ]; do
    echo "Waiting for SonarQube... (attempt $((SONAR_ATTEMPTS+1))/30)"
    sleep 20
    SONAR_ATTEMPTS=$((SONAR_ATTEMPTS+1))
done

if [ $SONAR_ATTEMPTS -gt 30 ]; then
    echo "[WARN] SonarQube took longer than expected to start, but continuing..."
else
    echo "[INFO] SonarQube is UP!"
fi

# -------------------------------
# Print Jenkins admin password and access info
# -------------------------------
echo "[INFO] ======== IMPORTANT ACCESS INFORMATION ========"
sleep 5
JENKINS_PASSWORD=$(sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || echo "Password not ready yet")
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "IP not available")

echo "[INFO] Jenkins Admin Password: $JENKINS_PASSWORD"
echo "[INFO] Public IP: $PUBLIC_IP"
echo "[INFO] Service URLs:"
echo "  - Jenkins:      http://$PUBLIC_IP:8080"
echo "  - SonarQube:    http://$PUBLIC_IP:9000 (admin/admin)"
echo "  - Frontend:     http://$PUBLIC_IP:3000"
echo "  - Backend API:  http://$PUBLIC_IP:3001"
echo "======================================================="

# -------------------------------
# Deploy amazon-clone application
# -------------------------------
echo "[INFO] Deploying amazon-clone application..."
REPO_URL="https://github.com/ARP-Proworks07/amazon-clone.git"
APP_DIR="/home/ubuntu/amazon-clone"

# Clean up any existing deployment
sudo docker rm -f amazon-clone-frontend amazon-clone-backend mongodb >/dev/null 2>&1 || true
sudo docker compose -f /home/ubuntu/amazon-clone/docker-compose.prod.yml down >/dev/null 2>&1 || true

if [ -d "$APP_DIR" ]; then
    echo "[INFO] Removing existing app directory..."
    sudo rm -rf "$APP_DIR"
fi

echo "[INFO] Cloning fresh copy of amazon-clone..."
sudo -u ubuntu git clone "$REPO_URL" "$APP_DIR"
sudo chown -R ubuntu:ubuntu "$APP_DIR"

cd "$APP_DIR" || exit 1

# Deploy using Docker Compose
if [ -f "docker-compose.prod.yml" ]; then
    echo "[INFO] Deploying with docker-compose.prod.yml..."
    
    # Create .env file for production
    cat > .env <<EOF
NODE_ENV=production
MONGODB_URI=mongodb://mongodb:27017/amazon-clone
JWT_SECRET=your-super-secret-jwt-key-change-in-production
PORT=3001
FRONTEND_URL=http://localhost:3000
BACKEND_URL=http://localhost:3001
EOF
    
    # Deploy with Docker Compose
    sudo docker compose -f docker-compose.prod.yml pull
    sudo docker compose -f docker-compose.prod.yml up -d --build
    
    echo "[INFO] Waiting for application services to be ready..."
    sleep 30
    
    # Check if services are running
    echo "[INFO] Application deployment status:"
    sudo docker compose -f docker-compose.prod.yml ps
    
elif [ -f "docker-compose.yml" ]; then
    echo "[INFO] Deploying with docker-compose.yml..."
    sudo docker compose -f docker-compose.yml up -d --build
else
    echo "[INFO] No compose file found, building manually..."
    
    # Start MongoDB
    sudo docker run -d --name mongodb --restart unless-stopped \
        -p 27017:27017 \
        -v mongodb_data:/data/db \
        mongo:latest
    
    # Build and run backend
    if [ -f "server/Dockerfile" ]; then
        cd server
        sudo docker build -t amazon-clone-backend .
        sudo docker run -d --name amazon-clone-backend --restart unless-stopped \
            -p 3001:3001 \
            --link mongodb:mongodb \
            -e MONGODB_URI=mongodb://mongodb:27017/amazon-clone \
            amazon-clone-backend
        cd ..
    fi
    
    # Build and run frontend
    if [ -f "Dockerfile" ]; then
        sudo docker build -t amazon-clone-frontend .
        sudo docker run -d --name amazon-clone-frontend --restart unless-stopped \
            -p 3000:3000 \
            amazon-clone-frontend
    fi
fi

echo "[INFO] Amazon Clone application deployment completed!"

# -------------------------------
# Reboot if required
# -------------------------------
if [ -f /var/run/reboot-required ]; then
    echo "[INFO] System reboot required. Rebooting..."
    sudo reboot
fi

echo "[INFO] ======== Bootstrap Completed Successfully ========="
