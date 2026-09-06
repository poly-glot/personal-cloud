# Project memory — runbooks & gotchas

Things future-me (or future-Claude) needs to know that aren't visible from reading the code.

---

## OKE Kubernetes upgrade runbook

Use this whenever bumping the cluster's Kubernetes version. Verified working on the v1.34.1 → v1.34.2 upgrade in April 2026, which initially failed in 4 different ways before settling. Verified again on v1.35.2 → v1.36.1 on 2026-09-06 (which also moved node OS from Oracle Linux 8.10 to 9.8 — ~35 min wall clock, ~4 min ingress downtime).

**There is no LTS in Kubernetes or OKE.** OKE supports three minors on a rolling window; upgrades are one minor at a time (`oci ce cluster list --query 'data[*]."available-kubernetes-upgrades"'` shows the only options). Take the latest patch of the next minor.

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

   **OS-jump trap:** `cluster.tf` picks the image with a *lexical* `reverse(sort(keys))[0]`, so `Oracle-Linux-9.x` beats `Oracle-Linux-8.x` regardless of build date. From 1.36.1 onward OKE ships both, and the picker silently chose OL 9.8 (cgroup v2, newer kernel). Decide this consciously: to hold the OS, tighten the regex to `Oracle-Linux-8.*aarch64.*OKE-${local.k8s_ver}-` and push that to main *before* running the workflow (the workflow applies from main).

   **OL 9 enforces registry short-name mode.** Namespaced image references without a registry host (`bitnami/kubectl:latest`, `curlimages/curl`) fail on OL 9 nodes with `short name mode is enforcing, but image name … returns ambiguous list` → `ImagePullBackOff`, and the pod never starts. OL 8 resolved these to Docker Hub silently. Single-name images (`busybox:latest`, `redis:7`) still work because OL 9 ships an alias table for the popular ones — that is why Traefik's `volume-permissions` init container survived. Qualify every image with its registry (`docker.io/…`). Verified 2026-09-06: `deployment/node-labeler/job.yaml` used `bitnami/kubectl:latest` and the workflow's `label-nodes` job would have failed on OL 9 nodes; it is now `docker.io/bitnami/kubectl:latest` (tag confirmed pulling on OL 9, kubectl v1.37.0 client). If Bitnami retires that tag (most free images moved to `bitnamilegacy/` in 2025), `docker.io/alpine/kubectl:<version>` is the fallback, but it has `sh` not `bash`.

3. **Audit PodDisruptionBudgets**:
   ```bash
   kubectl get pdb -A
   ```
   Any `minAvailable: N` where N >= deployment replicas means **drain will hang forever**. Either:
   - Convert to `maxUnavailable: 1`
   - Or scale the deployment to (N+1) replicas
   - Or, if downtime is acceptable, leave the PDB alone and drain with `--disable-eviction` (uses delete instead of the eviction API, which bypasses PDBs). Used on the Sept 2026 cycle for `ticketlist-api-develop/app-v1` (minAvailable 1, 1 replica; that namespace was removed on 2026-09-07 along with `ticketlist-api-main`).
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

**The workflow often reports overall `failure` even when the upgrade worked.** Observed May 2026: the `Wait for Node Pool to be Ready` job died at its "Configure Kubectl" step with `Unexpected HTTP response: 404` (a transient kubeconfig fetch on the runner), which then **skipped all downstream jobs** (Apply Node Labels, Deploy Traefik, Update NLB, Verify). The two jobs that matter — `Update Kubernetes Version in Code` and `Deploy Infrastructure Changes` — had already succeeded, so the control plane + node pool template were correctly on the new version. Check the *individual job* conclusions, not just the overall red X, then do the manual node-cycling below. Same 404 again in Sept 2026 — treat it as expected.

### ⚠️ AD-pinning trap (this WILL bite you — it caused real downtime on the v1.34.2 → v1.35.2 cycle, May 2026)

The RWO block volumes for **Traefik** (`oci-bv-traefik`, Retain) and **Redis master** (`oci-bv`) are **hard-pinned to `UK-LONDON-1-AD-1`** via PV `nodeAffinity` (`topology.kubernetes.io/zone In [UK-LONDON-1-AD-1]`). Verify with:

```bash
kubectl get pv $(kubectl -n kube-system get pvc traefik -o jsonpath='{.spec.volumeName}') -o jsonpath='{.spec.nodeAffinity}'
```

But the node pool's `placement_configs` span **AD-1, AD-2, AND AD-3** (terraform's `dynamic placement_configs for_each = local.azs`). So when you delete a node, **OKE can place the replacement in any AD**. If the node hosting Traefik/Redis (must be AD-1) gets replaced by a node in AD-2/AD-3, the pods go `Pending` forever with:

```
FailedScheduling: node(s) didn't match PersistentVolume's node affinity
```

Traefik is a **single replica with hard `nodeSelector: role=main`** — if its AD-1 node dies and the only `role=main` node is in another AD, ingress stays down.

**The fix that works: pin the node pool to AD-1 only BEFORE cycling, then the replacement is guaranteed AD-1.** Terraform's `lifecycle` block ignores `node_config_details[0].placement_configs`, so a CLI change here causes **no terraform drift**:

```bash
SUBNET=$(oci ce node-pool get --node-pool-id "$NODE_POOL_ID" --query 'data."node-config-details"."placement-configs"[0]."subnet-id"' --raw-output)
echo "[{\"availabilityDomain\":\"gRyn:UK-LONDON-1-AD-1\",\"subnetId\":\"$SUBNET\"}]" > /tmp/pc-ad1.json
oci ce node-pool update --node-pool-id "$NODE_POOL_ID" --placement-configs file:///tmp/pc-ad1.json \
  --force --wait-for-state SUCCEEDED
```

**Side effect to expect:** restricting placement to AD-1 makes OKE reconcile the *whole* pool into AD-1 — it will replace any existing AD-2/AD-3 node too. On the May 2026 cycle this collapsed a (AD-1 + AD-2) pair into two AD-1 nodes in one shot, which actually finished the upgrade faster but cost a brief Traefik outage while the new nodes came up unlabeled.

**Current state (left intentionally): `placement_configs` = AD-1 only.** This matches the AD-1-pinned volumes and makes node cycling reliable. It sacrifices AD-failure resilience — but the single-replica AD-1 volumes have no AD resilience anyway, so it's the honest config. To restore the 3-AD spread you'd re-run the CLI update with all three ADs, but expect OKE to immediately rebalance (cycling a node to AD-2/3 → Traefik breaks again). Don't restore casually.

**After cycling, new nodes come up with NO `role` label** → label them (`10.0.1.X role=main` for the Traefik/Redis node, the other `role=worker`) or Traefik stays `Pending`.

### Cycling nodes manually (the missing step)

Run after the workflow succeeds. **One node at a time** for minimum downtime. **Pin placement to AD-1 first (see AD-pinning trap above).**

**Order that minimises Traefik downtime:** cycle the `worker` node first. When its replacement is Ready, label the replacement `role=main` *before* draining the old `main` node — Traefik and Redis master then reschedule onto it immediately instead of sitting Pending until the second replacement is labelled. Label the second replacement `role=worker` when it arrives.

```bash
TENANCY=ocid1.tenancy.oc1..aaaaaaaaje52yql3f2nlli7zur5fvweb3xizhkmjbx65eocerfkqge7hkyaq
NODE_POOL_ID=$(oci ce node-pool list --compartment-id "$TENANCY" --query 'data[0].id' --raw-output)

# For each node still on the old version:
NODE_NAME=10.0.1.X    # kubectl name (the InternalIP)
NODE_OCID=$(oci ce node-pool get --node-pool-id "$NODE_POOL_ID" \
  --query "data.nodes[?\"private-ip\"=='$NODE_NAME' && \"lifecycle-state\"=='ACTIVE'].id | [0]" --raw-output)

kubectl cordon "$NODE_NAME"
# --disable-eviction only if a PDB would block and downtime is acceptable (see pre-flight 3)
kubectl drain "$NODE_NAME" --ignore-daemonsets --delete-emptydir-data --grace-period=60 --timeout=300s

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

The 03 stack uses `local.main_node_ip = local.active_nodes[0].private_ip` to derive backend IPs. Re-applying picks up the new node IP and updates `junaid-backend-set` (port 32080 → Traefik HTTP) and `junaid-backend-set-https` (port 32443 → Traefik HTTPS). Traefik's Service is NodePort with the default `externalTrafficPolicy: Cluster`, so any ACTIVE node works as the backend — it does not have to be the `role=main` node. You can run this as soon as the *first* replacement is ACTIVE; no need to wait for the second.

Check what the NLB actually points at (there are three NLBs in the tenancy; only `junaid-nlb` is terraform-managed — the two `ticketlist/ticketd-*-nlb` ones are created by `Service type=LoadBalancer` and the OCI cloud controller keeps their backends current on its own):

```bash
NLB=$(oci nlb network-load-balancer list --compartment-id "$TENANCY" --all --query 'data.items[?"display-name"==`junaid-nlb`].id | [0]' --raw-output)
oci nlb backend-set list --network-load-balancer-id "$NLB" --all --query 'data.items[*].{name:name,backends:join(`, `,backends[*].name)}' --output table
```

### Post-cycle: ensure node labels

Traefik has a hard `nodeSelector: role=main`; Redis master has a *preferred* (weight 100) affinity for `role=main`, so it follows Traefik. New nodes don't get these labels automatically. The kubernetes-upgrade workflow has a `label-nodes` job that runs `deployment/node-labeler/` (lowest lexically-sorted node name → `main`, rest → `worker`), but if the workflow failed mid-flight you may need to label manually. A later labeler run can flip which node is `main`; that does not evict running pods (nodeSelector is only enforced at scheduling time), it only changes where Traefik lands on its next restart.

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
for host in toolbox.junaid.guru directory.junaid.guru; do
  echo "$host: $(curl -s -o /dev/null -w '%{http_code}' -L -m 10 "https://$host/" 2>&1)"
done

# Pods all Running
kubectl get pods -A --no-headers | awk '$4!="Running"&&$4!="Completed"'
```

**ticketd replica does not re-follow a restarted leader — restart it (bit us 2026-09-06).** `ticketlist/ticketd` runs with `TICKETD_SYNC_STANDBYS=1` and `ZIGSTORE_QUORUM_DEADLINE_MS=15000`. When the node hosting the leader (`ticketd-0`) is cycled, the replica (`ticketd-1`) logs `receiver session ended: error.ConnectionClosed — reconnecting` and then never reconnects to the *new* leader pod (stale IP for `ticketd-0.ticketd`). The leader then has no sync standby, so **every write blocks for the 15 s quorum deadline** while reads stay fast. The Cloud Run edge (`ticketlist-edge`) times out at 10 s → users see "internal error" on join-queue, its logs say `engine timeout after 10000ms`, `/api/cart/start` takes 10012 ms, `/healthz/` 503. Pods all look Running; the tell is the agents' `/status` LSNs diverging (`wget -qO- http://<pod-ip>:7001/status` → `durableLsn` leader 114 vs replica 98) and the watchdog's `lagLsn` climbing. Fix: `kubectl -n ticketlist delete pod ticketd-1` — it reboots, fetches a base backup from the current leader, and LSNs converge within seconds. Do this after any node cycle that moved `ticketd-0`. (Real fix belongs in the ticketd agent: re-resolve the leader on reconnect.)

Fresh nodes show scary-looking transient events for the first ~2 minutes while daemonsets register: `FailedCreatePodSandBox … /run/flannel/subnet.env: no such file`, `CSINode … does not contain driver blockvolume.csi.oraclecloud.com`, and `FailedAttachVolume … device attribute /dev/oracleoci/oraclevdb is already in use` (two PVCs attaching at once). All self-heal. Don't act on them before the 3-minute mark.

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
for ns in toolbox dmozdb redis; do
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
- **NLB**: Network Load Balancers are **free** — the August 2026 usage report shows £0 for NLB with three running all month (`junaid-nlb` on 80/443/3306/33060, plus `ticketlist/ticketd-read-nlb` and `ticketlist/ticketd-leader-nlb` auto-created by `Service type=LoadBalancer`). The earlier "$17/mo" note was wrong; that price is for the L7 Load Balancer, which we don't use.
- **The only paid line item is block storage.** Verified via `oci usage-api usage-summary request-summarized-usages … --query-type COST --group-by '["resourceId","skuName"]'` for August 2026: total £6.84, all "Block Volume - Storage" + "Performance Units". Always Free covers 200 GB of boot + block combined; the two 47 GB OKE boot volumes plus the two 0-VPU volumes (Traefik, Redis) fit inside it. Every further 50 GB Balanced PV costs ≈ £1.70/mo (£1.02 storage + £0.68 performance units). Note a PVC requesting 1Gi or 10Gi still gets a 50 GB volume (OCI minimum), so the bill counts 50 GB per claim regardless of what the manifest asks for. Compute (2 × A1.Flex 2 OCPU/12 GB = exactly the 4 OCPU/24 GB ceiling), MySQL.Free, the BASIC OKE cluster, object storage and VCNs all bill £0.
- **NAT gateways**: free. Multiple stale gateways from old `oke-vcn-quick-*` VCNs are harmless cost-wise.
- **OCI auth tokens**: 2 per user max. Check quota before generating.
- **Customer Secret Keys** (S3-compat for OCI Object Storage): also 2 per user max. Used for terraform tfstate backend.
