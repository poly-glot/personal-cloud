# Redis Database

1 master + 1 replica setup with persistence (AOF + RDB) on OCI Kubernetes. Master runs on the `main` node, replica on the `worker` node. Each pod has 1Gi memory limit.

## Prerequisites

- `kubectl` configured with OCI kubeconfig
- Traefik ingress controller with Let's Encrypt
- DNS record for `redis.junaid.guru` pointing to your cluster

```bash
export KUBECONFIG=~/.kube/oci
```

## 1. Update Secrets

Replace placeholders before deploying:

**redis-secret.yaml** — set `<<redis-password-here>>` (3 occurrences)

**redis-config.yaml** — set `<<redis-password-here>>` in `requirepass` and `masterauth` for both master and replica (4 occurrences)

**redis-commander.yaml** — set `<<username-here>>` and `<<password-here>>` for basic auth

## 2. Deploy

```bash
kubectl apply -k redis-database/
```

## 3. Verify

```bash
# Watch pods come up
kubectl get pods -n redis -w

# Check replication status
kubectl exec -n redis deploy/redis-master -- redis-cli -a <your-password> info replication
```

You should see `connected_slaves:1` in the master's replication info.

## 4. Connect via CLI

```bash
kubectl apply -f redis-database/redis-cli-pod.yaml
kubectl exec -it -n redis redis-cli -- sh
redis-cli -h redis-master -a $REDIS_PASSWORD
```

Delete the CLI pod when done:

```bash
kubectl delete -f redis-database/redis-cli-pod.yaml
```

## 5. Redis Commander UI

Accessible at `https://redis.junaid.guru` (protected by basic auth).

## Services

| Service | DNS | Use |
|---------|-----|-----|
| `redis-master` | `redis-master.redis.svc.cluster.local:6379` | Read/Write |
| `redis-replica` | `redis-replica.redis.svc.cluster.local:6379` | Read-only |
| `redis-service` | `redis-service.redis.svc.cluster.local:6379` | Any pod |

## Connecting from Other Namespaces

Applications in other namespaces can use the secret values:

```yaml
env:
  - name: REDIS_URL
    valueFrom:
      secretKeyRef:
        name: redis-secret
        key: REDIS_URL
```

Or connect directly using the cross-namespace DNS:

```
redis-master.redis.svc.cluster.local:6379
```

## Uninstall

```bash
kubectl delete -k redis-database/
kubectl delete pvc redis-master-data redis-replica-data -n redis
```

Note: PVCs are not deleted by `kubectl delete -k` and must be removed manually to free the OCI Block Volumes.
