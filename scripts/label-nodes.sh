#!/bin/bash
# Script to label Kubernetes nodes with roles
# Usage: ./label-nodes.sh
#
# This script assigns roles to nodes:
# - First node: role=main (for Traefik/ingress)
# - Second node: role=mysql (for MySQL persistent storage)
# - Remaining nodes: role=worker

set -e

# Ensure KUBECONFIG is set
if [ -z "$KUBECONFIG" ]; then
  echo "KUBECONFIG not set. Setting to ~/.kube/oci"
  export KUBECONFIG=~/.kube/oci
fi

echo "Using KUBECONFIG: $KUBECONFIG"
echo ""

echo "Fetching all nodes..."
NODES=$(kubectl get nodes --no-headers -o custom-columns=":metadata.name" | sort)

if [ -z "$NODES" ]; then
  echo "ERROR: No nodes found"
  exit 1
fi

echo "Found nodes:"
echo "$NODES"
echo ""

# Convert to array
NODE_ARRAY=($NODES)
NODE_COUNT=${#NODE_ARRAY[@]}

echo "Total nodes: $NODE_COUNT"
echo ""

# First node gets role=main (for Traefik/ingress - NLB points to this node)
if [ $NODE_COUNT -ge 1 ]; then
  MAIN_NODE=${NODE_ARRAY[0]}
  echo "Labeling $MAIN_NODE with role=main..."
  kubectl label nodes "$MAIN_NODE" role=main --overwrite
fi

# All other nodes get role=worker
for ((i=1; i<$NODE_COUNT; i++)); do
  WORKER_NODE=${NODE_ARRAY[$i]}
  echo "Labeling $WORKER_NODE with role=worker..."
  kubectl label nodes "$WORKER_NODE" role=worker --overwrite
done

# Note: MySQL no longer needs a dedicated node label
# It uses OCI Block Volumes which persist across node recreation

echo ""
echo "Node labeling complete!"
echo ""
echo "Current node labels:"
kubectl get nodes --show-labels
