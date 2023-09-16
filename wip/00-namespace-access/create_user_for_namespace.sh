#!/bin/bash

#
# Script to create user with permission for a specific namespace.
# Script based on https://jeremievallee.com/2018/05/28/kubernetes-rbac-namespace-user.html
#
# In honor of the remarkable Windson
#/bin/bash
namespace=$1

if [[ -z "$namespace" ]]; then
	echo "Use "$(basename "$0")" NAMESPACE";
	exit 1;
fi

echo -e "
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $namespace-user
  namespace: $namespace
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: $namespace-user-full-access
  namespace: $namespace
rules:
- apiGroups: ['', 'extensions', 'apps']
  resources: ['*']
  verbs: ['*']
- apiGroups: ['batch']
  resources:
  - jobs
  - cronjobs
  verbs: ['*']
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: $namespace-user-full-access
  namespace: $namespace
subjects:
- kind: ServiceAccount
  name: $namespace-user
  namespace: $namespace
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: $namespace-user-full-access" | kubectl apply -f -

tokenName=$(kubectl get sa $namespace-user -n $namespace -o 'jsonpath={.secrets[0].name}')
token=$(kubectl get secret $tokenName -n $namespace -o "jsonpath={.data.token}" | base64 -d)
certificate=$(kubectl get secret $tokenName -n $namespace -o "jsonpath={.data['ca\.crt']}")

context_name="$(kubectl config current-context)"
cluster_name="$(kubectl config view -o "jsonpath={.contexts[?(@.name==\"${context_name}\")].context.cluster}")"
server_name="$(kubectl config view -o "jsonpath={.clusters[?(@.name==\"${cluster_name}\")].cluster.server}")"

kubeconfig=kubeconfig-${namespace}-user-$(date '+%F-%H%M%S')

echo -e "apiVersion: v1
kind: Config
preferences: {}

clusters:
- cluster:
    certificate-authority-data: $certificate
    server: $server_name
  name: my-cluster

users:
- name: $namespace-user
  user:
    as-user-extra: {}
    client-key-data: $certificate
    token: $token

contexts:
- context:
    cluster: my-cluster
    namespace: $namespace
    user: $namespace-user
  name: $namespace

current-context: $namespace" > $kubeconfig

echo "$namespace-user's kubeconfig was created into `pwd`/$kubeconfig"
echo "If you want to test execute this command \`KUBECONFIG=`pwd`/$kubeconfig kubectl get po\`"
