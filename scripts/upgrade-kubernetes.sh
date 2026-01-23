#!/bin/bash
# Kubernetes Upgrade Script for Oracle Cloud Infrastructure
# Usage: ./upgrade-kubernetes.sh <version>
# Example: ./upgrade-kubernetes.sh v1.35.0
#
# This script performs a complete Kubernetes upgrade:
# 1. Updates Terraform configuration with new version
# 2. Applies infrastructure changes
# 3. Waits for nodes to be ready
# 4. Labels nodes with roles
# 5. Deploys Traefik
# 6. Updates Network Load Balancer

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check arguments
if [ -z "$1" ]; then
  echo -e "${RED}Error: Kubernetes version required${NC}"
  echo "Usage: $0 <version>"
  echo "Example: $0 v1.35.0"
  exit 1
fi

NEW_VERSION="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Kubernetes Upgrade Script${NC}"
echo -e "${GREEN}======================================${NC}"
echo "Target Version: $NEW_VERSION"
echo "Project Root: $PROJECT_ROOT"
echo ""

# Ensure KUBECONFIG is set
if [ -z "$KUBECONFIG" ]; then
  echo -e "${YELLOW}KUBECONFIG not set. Setting to ~/.kube/oci${NC}"
  export KUBECONFIG=~/.kube/oci
fi

# Step 1: Update Terraform configuration
echo -e "${GREEN}Step 1: Updating Terraform configuration...${NC}"
cd "$PROJECT_ROOT/terraform/01-infrastructure"

sed -i.bak "s/kubernetes_version = \"v[0-9.]*\"/kubernetes_version = \"${NEW_VERSION}\"/g" cluster.tf
rm -f cluster.tf.bak

echo "Updated cluster.tf with version $NEW_VERSION"
grep "kubernetes_version" cluster.tf
echo ""

# Step 2: Apply infrastructure changes
echo -e "${GREEN}Step 2: Applying infrastructure changes...${NC}"
terraform init
terraform apply -auto-approve
echo ""

# Step 3: Wait for nodes to be ready
echo -e "${GREEN}Step 3: Waiting for nodes to be ready...${NC}"
MAX_ATTEMPTS=60
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo "0")
  TOTAL_NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")

  echo "Attempt $((ATTEMPT+1))/$MAX_ATTEMPTS: $READY_NODES/$TOTAL_NODES nodes ready"

  if [ "$READY_NODES" -ge 1 ] && [ "$READY_NODES" -eq "$TOTAL_NODES" ]; then
    echo -e "${GREEN}All $READY_NODES nodes are ready!${NC}"
    break
  fi

  ATTEMPT=$((ATTEMPT+1))
  sleep 30
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
  echo -e "${RED}Timeout waiting for nodes to be ready${NC}"
  kubectl get nodes
  exit 1
fi

kubectl get nodes
echo ""

# Step 4: Label nodes
echo -e "${GREEN}Step 4: Labeling nodes...${NC}"
"$SCRIPT_DIR/label-nodes.sh"
echo ""

# Step 5: Deploy Traefik
echo -e "${GREEN}Step 5: Deploying Traefik...${NC}"
cd "$PROJECT_ROOT/terraform/02-traefik"

helm repo add traefik https://traefik.github.io/charts 2>/dev/null || true
helm repo update

helm upgrade --install traefik traefik/traefik \
  --namespace kube-system --create-namespace -f values.yaml

kubectl apply -f http-to-https-redirect.yaml

echo "Waiting for Traefik to be ready..."
kubectl rollout status deployment/traefik -n kube-system --timeout=300s || {
  echo -e "${YELLOW}Warning: Traefik may not be fully ready${NC}"
  kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik
}
echo ""

# Step 6: Update Network Load Balancer
echo -e "${GREEN}Step 6: Updating Network Load Balancer...${NC}"
cd "$PROJECT_ROOT/terraform/03-network-loadbalancer"

terraform init
terraform apply -auto-approve

echo ""
echo "Network Load Balancer outputs:"
terraform output
echo ""

# Step 7: Verify deployment
echo -e "${GREEN}Step 7: Verifying deployment...${NC}"
echo ""
echo "=== Cluster Info ==="
kubectl cluster-info

echo ""
echo "=== Nodes ==="
kubectl get nodes -o wide

echo ""
echo "=== Node Labels ==="
kubectl get nodes --show-labels

echo ""
echo "=== Kubernetes Version ==="
kubectl version

echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Kubernetes Upgrade Complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo "Version: $NEW_VERSION"
echo ""
echo "Next steps:"
echo "1. Verify your applications are running correctly"
echo "2. Check ingress routes are accessible"
echo "3. Deploy MySQL if needed: kubectl apply -f mysql-database/mysql.yaml"
echo "4. Commit the version change: git add -A && git commit -m 'Upgrade Kubernetes to $NEW_VERSION'"
