# Namespace Access

```shell
openssl genrsa -out shehryar-user.key 4096
openssl req -new -key shehryar-user.key -out shehryar-user.csr -subj "/CN=shehryar-user"
cat  shehryar-user.csr | base64 | tr -d "\n"
kubectl create -f shehryar-csr.yaml
kubectl certificate approve shehryar-user
kubectl get csr shehryar-user -o jsonpath='{.status.certificate}'| base64 -d > shehryar-user.crt
cat  shehryar-user.crt | base64 | tr -d "\n" | pbcopy
kubectl get pods --kubeconfig=kubeconfig-shehryar-user --insecure-skip-tls-verify
```
