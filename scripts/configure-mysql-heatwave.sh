#!/bin/bash
# Configure MySQL HeatWave connection for Kubernetes applications
#
# Usage: ./configure-mysql-heatwave.sh
#
# Prerequisites:
# 1. MySQL HeatWave deployed via Terraform
# 2. KUBECONFIG set to your OKE cluster

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Configure MySQL HeatWave Connection${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""

# Ensure KUBECONFIG is set
if [ -z "$KUBECONFIG" ]; then
  echo -e "${YELLOW}KUBECONFIG not set. Setting to ~/.kube/oci${NC}"
  export KUBECONFIG=~/.kube/oci
fi

# Get MySQL HeatWave details from Terraform
echo "Fetching MySQL HeatWave details from Terraform..."
cd "$PROJECT_ROOT/terraform/05-mysql-heatwave"

if ! terraform output mysql_host &>/dev/null; then
  echo -e "${RED}Error: MySQL HeatWave not deployed or Terraform state not found${NC}"
  echo "Please run: cd terraform/05-mysql-heatwave && terraform apply"
  exit 1
fi

MYSQL_HOST=$(terraform output -raw mysql_host)
MYSQL_PORT=$(terraform output -raw mysql_port)

echo ""
echo -e "${GREEN}MySQL HeatWave Details:${NC}"
echo "Host: $MYSQL_HOST"
echo "Port: $MYSQL_PORT"
echo ""

# Prompt for credentials
read -p "Enter MySQL admin username [admin]: " MYSQL_USER
MYSQL_USER=${MYSQL_USER:-admin}

read -sp "Enter MySQL admin password: " MYSQL_PASSWORD
echo ""

read -p "Enter database name [app]: " MYSQL_DATABASE
MYSQL_DATABASE=${MYSQL_DATABASE:-app}

echo ""
echo "Updating mysql-database/mysql.yaml with HeatWave connection..."

# Update the mysql.yaml file
cd "$PROJECT_ROOT"

# Use sed to replace placeholders
sed -i.bak \
  -e "s|<<heatwave-ip-here>>|$MYSQL_HOST|g" \
  -e "s|<<password-here>>|$MYSQL_PASSWORD|g" \
  mysql-database/mysql.yaml

rm -f mysql-database/mysql.yaml.bak

echo -e "${GREEN}mysql-database/mysql.yaml updated!${NC}"
echo ""

# Apply to Kubernetes
read -p "Apply to Kubernetes cluster now? [Y/n]: " APPLY_NOW
APPLY_NOW=${APPLY_NOW:-Y}

if [[ "$APPLY_NOW" =~ ^[Yy]$ ]]; then
  echo "Applying MySQL connection resources to Kubernetes..."
  kubectl apply -k mysql-database/

  echo ""
  echo -e "${GREEN}MySQL HeatWave connection configured!${NC}"
  echo ""
  echo "Your apps can now connect using:"
  echo "  - Service DNS: mysql-service (ExternalName)"
  echo "  - Direct IP: $MYSQL_HOST:$MYSQL_PORT"
  echo "  - Environment variables from mysql-secret"
else
  echo ""
  echo "To apply later, run:"
  echo "  kubectl apply -k mysql-database/"
fi

echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Configuration Complete!${NC}"
echo -e "${GREEN}======================================${NC}"
