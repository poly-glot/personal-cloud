# Redis Database

Single-master Redis with persistence (AOF + RDB) on OCI Kubernetes. 1Gi memory limit.

The replica was removed to stay under the OCI Always Free 200 GB / 5-volume cap (each PVC provisions a 50 GB block volume). To re-introduce a replica, copy the master Deployment + a `redis-replica-data` PVC and add a `replica.conf` block to `redis-config.yaml`.

## Prerequisites

- `kubectl` configured with OCI kubeconfig
- Traefik ingress controller with Let's Encrypt
- DNS record for `redis.junaid.guru` pointing to your cluster

```bash
export KUBECONFIG=~/.kube/oci
```

## 1. Update Secrets

Replace placeholders before deploying:

**redis-secret.yaml** — set `<<redis-password-here>>` (2 occurrences)

**redis-config.yaml** — set `<<redis-password-here>>` in `requirepass` and `masterauth` (2 occurrences)

**redis-commander.yaml** — set `<<username-here>>` and `<<password-here>>` for basic auth

## 2. Deploy

```bash
kubectl apply -k redis-database/
```

## 3. Verify

```bash
# Watch pods come up
kubectl get pods -n redis -w

# Confirm master is responsive
kubectl exec -n redis deploy/redis-master -- redis-cli -a <your-password> ping
```

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
| `redis-service` | `redis-service.redis.svc.cluster.local:6379` | Any pod with `app=redis` selector |

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
kubectl delete pvc redis-master-data -n redis
```

Note: PVCs are not deleted by `kubectl delete -k` and must be removed manually to free the OCI Block Volume.
