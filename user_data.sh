#!/bin/bash
exec > /var/log/userdata.log 2>&1
set -xe

echo "[INFO] ======== Starting EC2 Bootstrap ========="

# --- Wait for apt locks ---
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
     echo "Waiting for apt lock..."
     sleep 10
done

# -------------------------------
# System Update & Tools
# -------------------------------
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y \
        docker.io git curl wget unzip openjdk-17-jdk apt-transport-https \
        ca-certificates gnupg lsb-release software-properties-common fontconfig conntrack jq docker-compose-plugin

# Enable Docker and add ubuntu user to group
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ubuntu || true
sudo chmod 666 /var/run/docker.sock || true

# -------------------------------
# Install K3s (Single Node)
# -------------------------------
curl -sfL https://get.k3s.io | sh -s - --disable traefik
sleep 30

# Configure kubeconfig for ubuntu
EC2_IP=$(hostname -I | awk '{print $1}')
mkdir -p /home/ubuntu/.kube
sudo sed "s/127.0.0.1/$EC2_IP/" /etc/rancher/k3s/k3s.yaml | sudo tee /home/ubuntu/.kube/config
sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube

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
if [ -z "$(sudo docker ps -q -f name=jenkins)" ]; then
    sudo docker run -d --name jenkins --restart unless-stopped \
        -p 8080:8080 -p 50000:50000 \
        -v jenkins_home:/var/jenkins_home \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v /usr/bin/docker:/usr/bin/docker \
        -v /usr/local/bin/kubectl:/usr/local/bin/kubectl \
        -v /usr/local/bin/k3s:/usr/local/bin/k3s \
        -v /usr/local/bin/ctr:/usr/local/bin/ctr \
        -v /run/k3s/containerd/containerd.sock:/run/k3s/containerd/containerd.sock \
        -v /home/ubuntu/.kube:/var/jenkins_home/.kube \
        --group-add $DOCKER_GID \
        --group-add $CONTAINERD_GID \
        jenkins/jenkins:lts-jdk17 || true
fi

# -------------------------------
# Run SonarQube container
# -------------------------------
sudo docker volume create sonarqube_data || true
sudo docker volume create sonarqube_extensions || true
sudo docker volume create sonarqube_logs || true

if [ -z "$(sudo docker ps -q -f name=sonarqube)" ]; then
    sudo docker run -d --name sonarqube --restart unless-stopped \
        -p 9000:9000 \
        -v sonarqube_data:/opt/sonarqube/data \
        -v sonarqube_extensions:/opt/sonarqube/extensions \
        -v sonarqube_logs:/opt/sonarqube/logs \
        sonarqube:lts-community || true
fi

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
echo "[INFO] Waiting for SonarQube..."
until curl -s http://localhost:9000/api/system/status | grep -q '"status":"UP"' ; do
    sleep 10
    echo "Waiting..."
done
echo "[INFO] SonarQube is UP!"

# -------------------------------
# Print Jenkins admin password
# -------------------------------
echo "[INFO] Jenkins admin password:"
sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword || true

# -------------------------------
# Deploy amazon-clone application
# -------------------------------
echo "[INFO] Deploying amazon-clone application..."
REPO_URL="https://github.com/ARP-Proworks07/amazon-clone.git"
APP_DIR="/home/ubuntu/amazon-clone"

if [ -d "$APP_DIR/.git" ]; then
    echo "[INFO] Repo already exists, pulling latest changes..."
    sudo -u ubuntu git -C "$APP_DIR" pull || sudo -u ubuntu git -C "$APP_DIR" fetch --all
else
    echo "[INFO] Cloning repo $REPO_URL to $APP_DIR"
    sudo -u ubuntu git clone "$REPO_URL" "$APP_DIR" || true
fi

sudo chown -R ubuntu:ubuntu "$APP_DIR" || true

# Ensure docker compose plugin/command is available
if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
    echo "[INFO] Installing docker compose plugin..."
    sudo apt-get install -y docker-compose-plugin || true
fi

cd "$APP_DIR" || exit 0

COMPOSE_FILE=""
if [ -f "docker-compose.prod.yml" ]; then
    COMPOSE_FILE="docker-compose.prod.yml"
elif [ -f "docker-compose.yml" ]; then
    COMPOSE_FILE="docker-compose.yml"
fi

if [ -n "$COMPOSE_FILE" ]; then
    echo "[INFO] Using compose file: $COMPOSE_FILE"
    # Use Docker Compose V2 (docker compose) if available, fallback to docker-compose
    if docker compose version >/dev/null 2>&1; then
        sudo docker compose -f "$COMPOSE_FILE" pull || true
        sudo docker compose -f "$COMPOSE_FILE" up -d --build || true
    else
        sudo docker-compose -f "$COMPOSE_FILE" pull || true
        sudo docker-compose -f "$COMPOSE_FILE" up -d --build || true
    fi
else
    echo "[WARN] No compose file found, attempting Dockerfile builds"
    # Build and run server if present
    if [ -f server/Dockerfile ]; then
        sudo docker build -t amazon-clone-server "$APP_DIR/server" || true
        sudo docker rm -f amazon-clone-server || true
        sudo docker run -d --name amazon-clone-server --restart unless-stopped -p 3001:3001 amazon-clone-server || true
    fi

    # Build frontend if top-level Dockerfile exists
    if [ -f Dockerfile ]; then
        sudo docker build -t amazon-clone-frontend "$APP_DIR" || true
        sudo docker rm -f amazon-clone-frontend || true
        sudo docker run -d --name amazon-clone-frontend --restart unless-stopped -p 3000:3000 amazon-clone-frontend || true
    fi
fi

echo "[INFO] amazon-clone deployment attempted. Check docker containers for status."

# -------------------------------
# Reboot if required
# -------------------------------
if [ -f /var/run/reboot-required ]; then
    echo "[INFO] System reboot required. Rebooting..."
    sudo reboot
fi

echo "[INFO] ======== Bootstrap Completed Successfully ========="
