# Project memory — runbooks & gotchas

Things future-me (or future-Claude) needs to know that aren't visible from reading the code.

---

## OKE Kubernetes upgrade runbook

Use this whenever bumping the cluster's Kubernetes version. Verified working on the v1.34.1 → v1.34.2 upgrade in April 2026, which initially failed in 4 different ways before settling.

### Pre-flight checks (do these before running the workflow)

1. **Confirm target version is supported by OKE**:
   ```
   open https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengaboutk8sversions.htm
   ```
   Look for the target version in the "currently supported" table. Note its planned EOL date.

2. **Verify an OKE-tagged image exists for the target version**:
   ```bash
   oci ce node-pool-options get --node-pool-option-id all \
     --query 'data."sources"[?contains("source-name",`aarch64`) && contains("source-name",`OKE-1.34.2-`)] | reverse(sort_by(@,&"source-name")) | [0]'
   ```
   If empty, the node pool stage of the upgrade will fail with `Invalid index` (data source returns empty list). Replace `1.34.2` with the target.

3. **Audit PodDisruptionBudgets**:
   ```bash
   kubectl get pdb -A
   ```
   Any `minAvailable: N` where N >= deployment replicas means **drain will hang forever**. Either:
   - Convert to `maxUnavailable: 1`
   - Or scale the deployment to (N+1) replicas
   - The OKE node pool eviction policy should already be `isForceDeleteAfterGraceDuration: true` (1h timeout); confirm with:
     ```bash
     oci ce node-pool get --node-pool-id $(oci ce node-pool list --compartment-id <tenancy> --query 'data[0].id' --raw-output) \
       --query 'data."node-eviction-node-pool-settings"'
     ```

4. **Verify ocirsecret exists in `default` namespace and every app namespace**:
   ```bash
   kubectl get secret ocirsecret --all-namespaces 2>&1 | grep ocirsecret
   ```
   If missing in any namespace pulling from OCIR, new pods on freshly-cycled nodes will hit `ImagePullBackOff` with `denied: Anonymous users…`. Recreate via the [ocirsecret recovery](#ocirsecret-recovery) section below.

5. **Check single points of failure for stateful workloads**:
   - Traefik PV (oci-bv-traefik SC, RWO Retain) — must reattach after node cycle. Pod will be Pending with FailedScheduling until OCI reattaches the volume + the new node has the `role=main` label.
   - Redis master PVC (RWO) — same, but on `oci-bv` SC with Delete reclaim.
   - Any other RWO PVCs.

6. **Sanity baseline**:
   ```bash
   kubectl get nodes -o 'custom-columns=NAME:.metadata.name,STATUS:.status.conditions[-1].type,VERSION:.status.nodeInfo.kubeletVersion'
   kubectl get pods -A --no-headers | awk '$4!="Running"&&$4!="Completed"'
   ```
   Should be an empty list of broken pods. Don't start an upgrade with broken state — you won't be able to tell what broke from the upgrade vs what was already broken.

### Running the upgrade

```bash
gh workflow run kubernetes-upgrade.yaml --repo poly-glot/personal-cloud --ref main \
  -f kubernetes_version=v1.34.2
```

**The workflow does NOT cycle existing nodes.** It updates the node pool template (kubernetes_version + image) but existing VMs keep running their old kubelet/image until replaced. The workflow's `wait-for-nodes` step only checks that nodes are Ready (which they will be — on the OLD version). After the workflow's "successful" completion, you may still see old kubelets via `kubectl get nodes`.

### Cycling nodes manually (the missing step)

Run after the workflow succeeds. **One node at a time** for minimum downtime:

```bash
TENANCY=ocid1.tenancy.oc1..aaaaaaaaje52yql3f2nlli7zur5fvweb3xizhkmjbx65eocerfkqge7hkyaq
NODE_POOL_ID=$(oci ce node-pool list --compartment-id "$TENANCY" --query 'data[0].id' --raw-output)

# For each node still on the old version:
NODE_NAME=10.0.1.X    # kubectl name (the InternalIP)
NODE_OCID=ocid1.instance.oc1.uk-london-1.XXX  # from `oci ce node-pool get`

kubectl cordon "$NODE_NAME"
kubectl drain "$NODE_NAME" --ignore-daemonsets --delete-emptydir-data --grace-period=60 --timeout=240s

# CRITICAL: --is-decrement-size false. Default decrements pool size, no replacement created.
oci ce node-pool delete-node \
  --node-pool-id "$NODE_POOL_ID" \
  --node-id "$NODE_OCID" \
  --is-decrement-size false \
  --force

# Wait for replacement Ready before doing the next node
until kubectl get nodes --no-headers | grep -E "Ready " | wc -l | grep -q 2; do sleep 15; done
```

### Post-cycle: re-apply NLB stack (otherwise traffic dies)

When old nodes are deleted, NLB backend IPs still point at the dead nodes. **All ingress (web traffic) goes to a black hole until this is run**.

```bash
gh workflow run terraform-network-loadbalancer.yaml --repo poly-glot/personal-cloud --ref main
```

The 03 stack uses `local.main_node_ip = local.active_nodes[0].private_ip` to derive backend IPs. Re-applying picks up the new node IP and updates `junaid-backend-set` (port 32080 → Traefik HTTP) and `junaid-backend-set-https` (port 32443 → Traefik HTTPS).

### Post-cycle: ensure node labels

Traefik has `nodeSelector: role=main` and Redis master has `nodeAffinity` on `role: worker`. New nodes don't get these labels automatically. The kubernetes-upgrade workflow has a `label-nodes` job that runs `deployment/node-labeler/`, but if the workflow failed mid-flight you may need to label manually:

```bash
kubectl label node 10.0.1.X role=main --overwrite
kubectl label node 10.0.1.Y role=worker --overwrite
```

(The convention so far: pick one node as `main`, rest as `worker`. Traefik wants `main`.)

### Verification

```bash
# All nodes on target version + Ready
kubectl get nodes
oci ce node-pool list --compartment-id "$TENANCY" --query 'data[*].{name:name,"k8s":"kubernetes-version"}'

# All ingress hosts reachable
for host in toolbox.junaid.guru ticketlist-api.junaid.guru shehryar.dev; do
  echo "$host: $(curl -s -o /dev/null -w '%{http_code}' -L -m 10 "https://$host/" 2>&1)"
done

# Pods all Running
kubectl get pods -A --no-headers | awk '$4!="Running"&&$4!="Completed"'
```

### Estimated downtime

- **Control plane upgrade**: ~5–10 min, no workload impact (kubelets keep talking to old API server which is rolling).
- **Per node cycle**: ~5–8 min replacement + drain time. RWO-PVC workloads (Traefik, Redis master) move = brief downtime per cycle.
- **NLB backend re-apply**: ~30s, but **all HTTP/HTTPS traffic is down between node cycle and NLB apply** if you forget the post-cycle step. Don't forget.

Total: 30–60 min for a 2-node cluster, with ~5 min visible downtime per ingress host (single Traefik replica means no HA).

---

## ocirsecret recovery

If ocirsecret is missing or stale, every fresh image pull from OCIR fails with `denied: Anonymous users are only allowed read access`.

```bash
# OCI auth token (legacy, free, max 2 per user). Quota check:
USER_ID=ocid1.user.oc1..aaaaaaaaedaopebst3ct5zy4grlijiho3tdyxawx4rpk6epcveegtuwsjafa
oci iam auth-token list --user-id "$USER_ID"

# Create one (token shown ONCE in response, capture it):
TOKEN=$(oci iam auth-token create --user-id "$USER_ID" --description "OCIR ocirsecret $(date +%Y-%m-%d)" \
  --query 'data.token' --raw-output)

# Mirror to GSM for future readability:
echo -n "$TOKEN" | gcloud secrets versions add oci-auth-token-ocirsecret --data-file=- --project=firebase-cloud-491613

# Create secret in default. NOTE: do NOT name the bash var USERNAME — zsh
# treats USERNAME as a built-in variable that holds the OS user. Use OCIR_USER.
OCIR_USER='lrhvckxzwf3l/oracleidentitycloudservice/junaid@simpleux.co.uk'
kubectl delete secret ocirsecret -n default --ignore-not-found
kubectl create secret docker-registry ocirsecret \
  --docker-server=lhr.ocir.io \
  --docker-username="$OCIR_USER" \
  --docker-password="$TOKEN" \
  --namespace=default

# Copy to every namespace pulling from OCIR
for ns in toolbox ticketlist-api-main ticketlist-api-develop redis; do
  kubectl delete secret ocirsecret -n "$ns" --ignore-not-found
  kubectl get secret ocirsecret -n default -o yaml \
    | sed "s/namespace: default/namespace: $ns/" \
    | kubectl create -f -
done
```

Long-term fix: switch OKE to **Instance Principal** auth for OCIR (no token rotation, no per-namespace copying). Requires a one-time IAM dynamic group + policy. Not done yet.

---

## OCI Container Registry — what NOT to delete

`oci artifacts container image delete` on an "untagged" image is dangerous.

OCIR multi-arch images use a **manifest list** (index) at the tag, which references per-platform child manifests that themselves are untagged. Deleting an untagged child leaves the tag pointing at a list that can't resolve, and `kubelet` fails with `manifest unknown`. **Old nodes hide this** because they have layers cached locally; new nodes (post node-cycle) can't pull.

Safe pruning:

- Walk every tagged manifest and exclude the digests it references.
- Or just keep ALL manifests within an N-day window regardless of tag status.
- **Tag versions are full git SHAs (40 chars), not 20**. Truncating in `kubectl set image` produces `manifest unknown`.

Side-effect from April 2026 cleanup: shehryar/ticketlist-api/toolbox images broke when the cluster cycled to new nodes. Recovery required pushing fresh builds from each app repo.

---

## Cross-repo MySQL provisioning

See `docs/superpowers/specs/2026-04-25-mysql-app-provisioning-design.md`. Adding a new app DB:

1. In `firebase-cloud`: edit `terraform/apps/<app>.tf`, add `module "<app>_db"` with `source = "../modules/app-with-mysql"`. Add to `locals.mysql_apps` in `mysql-catalog.tf`. Push to main.
2. firebase-cloud auto-applies → creates SA, secret shells (`<app>-db-{user,pass,name}`), IAM bindings, updates `mysql-app-catalog` GSM secret, and dispatches personal-cloud's `terraform-mysql-apps.yaml`.
3. personal-cloud workflow reads catalog → provisions OCI MySQL DB + user + writes secret versions.
4. App's Cloud Run reads the GSM secrets via `secret_key_ref`.

Stale MySQL admin creds live in GSM as `db-admin-user` / `db-admin-pass`. OCI tfstate creds live in GSM as `oci-tf-aws-access-key-id` / `oci-tf-aws-secret-access-key`.

---

## OCI free-tier facts that bit me

- **Block volume minimum**: 50 GB. Kubernetes PVCs requesting `1Gi` get a 50 GiB volume. Cannot shrink.
- **Volume backup billing**: orphan backups from deleted boot volumes still cost ~$0.018/GB·mo on `unique-size-in-gbs`. The bronze policy backup naming `Auto-backup ... via policy: bronze` indicates auto-attached policy from console (not terraform). Check periodically.
- **NLB**: 1 included in Always Free. Second NLB ≈ $17/mo. Consolidated to one (`junaid-nlb`) handling 80, 443, 3306, 33060.
- **NAT gateways**: free. Multiple stale gateways from old `oke-vcn-quick-*` VCNs are harmless cost-wise.
- **OCI auth tokens**: 2 per user max. Check quota before generating.
- **Customer Secret Keys** (S3-compat for OCI Object Storage): also 2 per user max. Used for terraform tfstate backend.
