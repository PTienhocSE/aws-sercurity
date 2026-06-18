#!/bin/bash
# ==============================================================================
# Setup Script for AWS EC2 (Ubuntu) - K8s + ArgoCD Platform
# ==============================================================================
set -e

echo "=== 1. Updating package list & installing prerequisites ==="
sudo apt-get update -y
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    jq

echo "=== 2. Installing Docker Engine ==="
if ! command -v docker &> /dev/null; then
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

# Add current user to docker group
sudo usermod -aG docker $USER
echo "Adding user $USER to the docker group..."

echo "=== 3. Installing Kind (Kubernetes in Docker) ==="
if ! command -v kind &> /dev/null; then
    KIND_VERSION="v0.22.0"
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
fi

echo "=== 4. Installing kubectl ==="
if ! command -v kubectl &> /dev/null; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/kubectl
fi

echo "=== 5. Installing Helm ==="
if ! command -v helm &> /dev/null; then
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

echo "=== 6. Creating Kind Cluster with Host Port Mappings ==="
# Create Kind configuration to map host ports 8080 (http) and 8443 (https) to control plane
cat <<EOF > kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080
    hostPort: 8080
    protocol: TCP
  - containerPort: 30443
    hostPort: 8443
    protocol: TCP
EOF

# Delete existing cluster if any
kind delete cluster --name security-lab || true
# Create new cluster
sg docker -c "kind create cluster --name security-lab --config kind-config.yaml"

# Set up kubeconfig
mkdir -p $HOME/.kube
sudo cp /root/.kube/config $HOME/.kube/config || sg docker -c "kind get kubeconfig --name security-lab > $HOME/.kube/config"
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo "=== 7. Installing ArgoCD ==="
kubectl create namespace argocd || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.4/manifests/install.yaml

echo "=== 8. Patching ArgoCD Service to use NodePort (port 30443) ==="
# Patch ArgoCD server to run as NodePort on port 30443 for external access
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort", "ports": [{"port": 443, "nodePort": 30443, "protocol": "TCP", "name": "https"}]}}'

echo "=== Waiting for ArgoCD Server to become ready ==="
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

echo "=== 9. Retrieving ArgoCD initial admin password ==="
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode)

echo "=============================================================================="
echo " SETUP COMPLETED SUCCESSFULLY!"
echo "=============================================================================="
echo "Kubernetes cluster is up and ArgoCD is running."
echo ""
echo "Access ArgoCD UI:"
echo "  URL:      https://<EC2-PUBLIC-IP>:8443"
echo "  Username: admin"
echo "  Password: $ARGOCD_PASSWORD"
echo ""
echo "Note: Make sure your EC2 Security Group allows INBOUND TCP traffic on port 8443."
echo "=============================================================================="
