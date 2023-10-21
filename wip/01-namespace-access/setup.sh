#!/bin/bash

if [ $# -lt 2 ]; then
  echo "Usage: $0 <username> <namespace1> <namespace2> ..."
  exit 1
fi

username="$1"
shift 1  # Remove the first argument (username)

# Iterate over the supplied namespaces and create role bindings
for namespace in "$@"; do
  # Create the Kubernetes namespace
  kubectl create namespace "${namespace}"

  # Create a Kubernetes ServiceAccount for the user in the namespace
  kubectl create serviceaccount "${username}-sa" -n "${namespace}"

  # Bind the ServiceAccount to a Role (e.g., view) to grant access
  kubectl create rolebinding "${username}-rolebinding" --clusterrole=view --serviceaccount="${namespace}:${username}-sa" --namespace="${namespace}"

  echo "User $username has access to namespace $namespace"
done

# Get the Secret containing the user's token from the first namespace
first_namespace="$1"
secret_name=$(kubectl get serviceaccount "${username}-sa" -n "${first_namespace}" -o jsonpath='{.secrets[0].name}')
token=$(kubectl get secret "${secret_name}" -n "${first_namespace}" -o jsonpath='{.data.token}' | base64 --decode)

# Get the Kubernetes cluster information
cluster_name=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
server_url=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

# Generate a kubeconfig file for the user
cat <<EOF > "${username}-kubeconfig.yaml"
apiVersion: v1
kind: Config
preferences: {}
clusters:
- cluster:
    certificate-authority-data: $(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
    server: $server_url
  name: $cluster_name
contexts:
- context:
    cluster: $cluster_name
    user: $username
    namespace: $first_namespace
  name: $username-context
current-context: $username-context
users:
- name: $username
  user:
    token: $token
EOF

echo "Kubeconfig file created: ${username}-kubeconfig.yaml"
