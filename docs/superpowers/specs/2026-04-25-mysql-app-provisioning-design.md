# Design: MySQL App Provisioning Across personal-cloud + firebase-cloud

**Date**: 2026-04-25
**Status**: Approved (brainstorming complete; pending implementation plan)
**Repos affected**: `poly-glot/personal-cloud`, `poly-glot/firebase-cloud`

## Goal

Adding a new app to firebase-cloud that needs an OCI MySQL database should be a **one-file edit + push** with no manual coordination between repos and no risk of naming-mismatch bugs. Operators (and Claude) must be able to read all credentials through `gcloud secrets versions access` for debugging.

## Background: what's broken today

The two repos drifted into a state where:

1. Both repos try to *create* the same `{app}-db-{user,pass,name}` GSM secrets (`firebase-cloud/terraform/apps/shehryar.tf:61-83` and `personal-cloud/terraform/06-mysql-apps/apps.tf:29-51`). Whichever runs second hits 409.
2. There is no shared SA naming contract — `personal-cloud/.../variables.tf:42` hard-codes `shehryar-run@...` while `firebase-cloud/modules/app-identity/main.tf:28` actually creates `${app}-runtime`. Two strings, no compiler can catch a mismatch.
3. MySQL admin credentials live only in GitHub Actions secrets (`DB_USER`/`DB_PASS`), unreadable for debugging. They are duplicated in GSM (`db-admin-user`/`db-admin-pass`) but the workflow doesn't read from there.
4. Adding an app requires editing both repos in a specific order, with no documentation of that order. Errors surface only at apply time as obscure 4xx errors from Google APIs.

Recent failed runs: `gh run view 24860969329 --repo poly-glot/personal-cloud`, `gh run view 24914792853`. Each fix exposed the next layer of breakage — symptom of structural rather than tactical bugs.

## Architecture

Two repos with one explicit contract: a GSM secret named `mysql-app-catalog` containing JSON declared by firebase-cloud and consumed by personal-cloud.

```
firebase-cloud (declares apps + their needs)
        │
        │ writes JSON to GSM secret `mysql-app-catalog`:
        │   { shehryar: { database: "rn_chatapp",
        │                 sa_email: "shehryar-runtime@..." }, ... }
        │
        │ on apply, dispatches:
        │   gh workflow run terraform-mysql-apps.yaml
        ▼
personal-cloud (provisions OCI MySQL DBs + populates secret values)
```

**Ownership rule**: each repo creates IAM bindings only for resources it owns. This single principle removes the round-and-round.

### Resource ownership

| Resource | Owner | Reason |
|---|---|---|
| App SA `{app}-runtime@firebase-cloud-491613.iam.gserviceaccount.com` | firebase-cloud | `app-identity` module already creates it |
| GSM secret shells `{app}-db-{user,pass,name}` | firebase-cloud | App declares which secrets it needs |
| GSM secret IAM bindings (runtime SA → its own secrets) | firebase-cloud | Owns both the SA and the shells |
| GSM `mysql-app-catalog` (shell + version) | firebase-cloud | It is the contract output |
| GSM `db-host` shell (existing) | firebase-cloud | Already does — keep |
| OCI MySQL `mysql_database`, `mysql_user`, `mysql_grant` | personal-cloud | Owns the OCI MySQL connection |
| `random_password` per app | personal-cloud | Generates the password |
| GSM secret *versions* (writes data into firebase-cloud's shells) | personal-cloud | Knows the password and DB name |
| GSM `db-admin-user` / `db-admin-pass` (shell + version) | personal-cloud | MySQL admin creds — pair with the cluster it manages |
| IAM bindings: personal-cloud deploy SA → bootstrap secrets | firebase-cloud | Avoids personal-cloud chicken-and-egg (needs the secrets to apply) |

## Components

### firebase-cloud changes

**New module** `terraform/modules/app-with-mysql/`:
- Inputs: `app_name`, `database_name`, `runtime_sa_email`
- Creates: 3 × `google_secret_manager_secret` (`{app}-db-{user,pass,name}`), 4 × `google_secret_manager_secret_iam_member` (runtime SA → 3 shells + `db-host`)
- Outputs: `app_entry = { database = var.database_name, sa_email = var.runtime_sa_email }` for the catalog

**New file** `terraform/apps/mysql-catalog.tf`:
- `locals.mysql_apps = { shehryar = module.shehryar_db.app_entry, ... }`
- `google_secret_manager_secret "mysql_app_catalog"` (shell, always created — even when `local.mysql_apps == {}`)
- `google_secret_manager_secret_version "mysql_app_catalog"` with `secret_data = jsonencode(local.mysql_apps)`
- IAM bindings granting `var.personal_cloud_deploy_sa` reader access to: `mysql-app-catalog`, `db-admin-user`, `db-admin-pass`, `oci-tf-aws-access-key-id`, `oci-tf-aws-secret-access-key`

**New variable** `terraform/variables.tf`:
- `variable "personal_cloud_deploy_sa"` (string, hardcoded value matches `INFRA_GCP_SA_EMAIL` GitHub secret)

**Modified** `terraform/apps/shehryar.tf`:
- Remove the 3 `google_secret_manager_secret "shehryar_db_*"` blocks (`:61-83`)
- Add `module "shehryar_db" { source = "../modules/app-with-mysql"; app_name = "shehryar"; database_name = "rn_chatapp"; runtime_sa_email = module.shehryar_identity.runtime_sa_email }`
- Cloud Run secret refs unchanged (still reference by `secret_id`)

**Modified** `.github/workflows/terraform.yml`:
- Add a step to the `apply` job (after `Terraform Apply`, line 141) that unconditionally dispatches `terraform-mysql-apps.yaml`:
  ```yaml
  - name: Trigger personal-cloud MySQL provisioning
    env:
      GH_TOKEN: ${{ secrets.MYSQL_APPS_DISPATCH_TOKEN }}
    run: gh workflow run terraform-mysql-apps.yaml --repo poly-glot/personal-cloud --ref main
  ```
- Dispatch is unconditional (no version-change detection) — personal-cloud apply is idempotent, and conditional dispatch can have false-negatives that leave apps unprovisioned.

### personal-cloud changes

**Modified** `terraform/06-mysql-apps/data.tf`:
- Add `data "google_secret_manager_secret_version" "mysql_app_catalog" { secret = "mysql-app-catalog" }`
- Add `locals.apps = jsondecode(data.google_secret_manager_secret_version.mysql_app_catalog.secret_data)`

**Modified** `terraform/06-mysql-apps/apps.tf`:
- Replace all `for_each = var.apps` with `for_each = local.apps` (3 resources: `random_password`, `mysql_database`, `mysql_user`, `mysql_grant`).
- Delete `google_secret_manager_secret "app_user/app_pass/app_name"` (`:29-51`) — owned by firebase-cloud now.
- Add `data "google_secret_manager_secret" "app_user/app_pass/app_name"` (3 data sources, for_each).
- Keep `google_secret_manager_secret_version` blocks; reference `data.google_secret_manager_secret.app_user[each.key].id`.
- Delete `google_secret_manager_secret_iam_member "app_access"` block (`:90-95`) and the `locals.app_secret_bindings` (`:71-88`) — owned by firebase-cloud now.

**Modified** `terraform/06-mysql-apps/variables.tf`:
- Delete `variable "apps"` block (`:33-45`) entirely.
- Keep `variable "mysql_admin_username"` and `variable "mysql_admin_password"` — still referenced by `providers.tf:11-12` and `cluster-secrets.tf:20,32`. Their values now arrive as `TF_VAR_*` env vars set by the workflow's GSM-fetch step (not from GitHub secrets).

**Modified** `terraform/06-mysql-apps/outputs.tf`:
- Replace `for app, cfg in var.apps` (`:4`) with `for app, cfg in local.apps`.
- Field rename: `cfg.service_account` → `cfg.sa_email` to match the catalog JSON schema.

**Modified** `.github/workflows/terraform-mysql-apps.yaml`:
- After `google-github-actions/auth@v2`, add:
  ```yaml
  - name: Load creds from Secret Manager
    id: creds
    uses: google-github-actions/get-secretmanager-secrets@v2
    with:
      secrets: |-
        MYSQL_ADMIN_USER:firebase-cloud-491613/db-admin-user
        MYSQL_ADMIN_PASS:firebase-cloud-491613/db-admin-pass
        OCI_TF_AWS_KEY:firebase-cloud-491613/oci-tf-aws-access-key-id
        OCI_TF_AWS_SECRET:firebase-cloud-491613/oci-tf-aws-secret-access-key
  - name: Export to terraform env
    run: |
      echo "TF_VAR_mysql_admin_username=${{ steps.creds.outputs.MYSQL_ADMIN_USER }}" >> $GITHUB_ENV
      echo "TF_VAR_mysql_admin_password=${{ steps.creds.outputs.MYSQL_ADMIN_PASS }}" >> $GITHUB_ENV
      echo "AWS_ACCESS_KEY_ID=${{ steps.creds.outputs.OCI_TF_AWS_KEY }}" >> $GITHUB_ENV
      echo "AWS_SECRET_ACCESS_KEY=${{ steps.creds.outputs.OCI_TF_AWS_SECRET }}" >> $GITHUB_ENV
  ```
- Remove `TF_VAR_mysql_admin_*`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` from the workflow's top-level `env:` block.

**Modified** `.github/workflows/terraform-mysql-heatwave.yaml`:
- Same `get-secretmanager-secrets` pattern (also needs MySQL admin creds + AWS for tfstate).

### New GSM secrets (one-time manual setup)

| Secret | Value source |
|---|---|
| `mysql-app-catalog` | Created by firebase-cloud terraform on first apply — no manual write needed |
| `oci-tf-aws-access-key-id` | Rotate the unused 2025 OCI Customer Secret Key into here |
| `oci-tf-aws-secret-access-key` | Same |

### GitHub secrets

**To delete after migration verified** (both repos): `DB_USER`, `DB_PASS`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`.

**To add** (firebase-cloud only): `MYSQL_APPS_DISPATCH_TOKEN` — fine-grained PAT, scope `actions:write` on `poly-glot/personal-cloud` only, no other scopes.

**To keep** (bootstrap only): `INFRA_WIF_PROVIDER`, `INFRA_GCP_SA_EMAIL`, `OCI_*` (auth — stable, rarely rotated).

## Data flow

### Flow A — Adding a new app `fooapp` (steady state)

1. Developer edits `firebase-cloud/terraform/apps/fooapp.tf`:
   ```hcl
   module "fooapp_identity" { source = "../modules/app-identity"; app_name = "fooapp"; ... }
   module "fooapp_db"       { source = "../modules/app-with-mysql"
                              app_name         = "fooapp"
                              database_name    = "fooapp_db"
                              runtime_sa_email = module.fooapp_identity.runtime_sa_email }
   ```
   Adds `fooapp = module.fooapp_db.app_entry` to `locals.mysql_apps` in `mysql-catalog.tf`. Push to `main`.
2. firebase-cloud workflow plan + apply (auto, gated by `production` environment if approval is configured): creates `fooapp-runtime@...` SA, 3 secret shells, 4 IAM bindings (3 + `db-host`), updates `mysql-app-catalog` secret version.
3. Workflow's final step runs `gh workflow run terraform-mysql-apps.yaml --repo poly-glot/personal-cloud`.
4. personal-cloud workflow runs:
   - Reads `mysql-app-catalog` → `local.apps` includes `fooapp`
   - Reads 3 shell data sources for `fooapp`
   - Creates `mysql_database "fooapp_db"`, `mysql_user "fooapp"` with `random_password`, `mysql_grant`
   - Writes `secret_version` on each of the 3 shells
5. fooapp's runtime SA can now read the populated secrets; Cloud Run is unblocked.

Wall-clock: ~3 minutes total.

### Flow B — Updating an existing app's database name

**Not supported.** `database_name` is immutable in this design. Renaming would force a destroy+create on `mysql_database`, losing data. If a rename is needed, do it manually with the `mysql` client and `terraform import` — outside this design's scope.

### Flow C — Removing an app (two-step)

1. **First push**: remove the app's entry from `locals.mysql_apps` in `mysql-catalog.tf` (but keep `apps/{app}.tf` intact). firebase-cloud apply updates the catalog. personal-cloud apply destroys the MySQL database, user, grants, and the secret versions it owned.
2. **Second push**: delete `apps/{app}.tf`. firebase-cloud apply destroys the SA, secret shells, IAM bindings.

This split prevents firebase-cloud from destroying secret shells while personal-cloud's `secret_version` resources still reference them.

### Flow D — First-time bootstrap

1. Manually rotate the 2025 OCI Customer Secret Key into GSM as `oci-tf-aws-access-key-id` and `oci-tf-aws-secret-access-key`. (See migration phase 1.)
2. Apply firebase-cloud terraform once with `local.mysql_apps == {}`. Creates the empty `mysql-app-catalog` secret + version `{}`. Confirms the catalog mechanism without provisioning anything.
3. Migrate shehryar following migration phases 2–3.

The catalog secret is created unconditionally by firebase-cloud terraform (even when no apps have DBs), so personal-cloud's data source always finds it.

### Flow E — Credential lookup at workflow start (every apply)

```
Workflow start
  └─→ google-github-actions/auth@v2 (WIF via INFRA_WIF_PROVIDER + INFRA_GCP_SA_EMAIL)
        └─→ get-secretmanager-secrets@v2:
              db-admin-user           → MYSQL_ADMIN_USER
              db-admin-pass           → MYSQL_ADMIN_PASS
              oci-tf-aws-access-key-id     → OCI_TF_AWS_KEY
              oci-tf-aws-secret-access-key → OCI_TF_AWS_SECRET
              └─→ Export to GITHUB_ENV as TF_VAR_*, AWS_ACCESS_KEY_ID/SECRET
                    └─→ terraform init (S3 backend uses AWS_*)
                          └─→ terraform apply
```

## Error handling

| Failure | Symptom | Recovery |
|---|---|---|
| firebase-cloud apply succeeds, dispatch step fails | Catalog updated, personal-cloud doesn't run | Re-run `terraform-mysql-apps.yaml` manually — it's idempotent |
| personal-cloud apply runs before firebase-cloud finishes | `data.google_secret_manager_secret` 404 | Plan fails fast; re-run after firebase-cloud settles. Unlikely because dispatch happens after firebase-cloud apply step completes |
| MySQL admin creds wrong/rotated | TLS or auth error from MySQL provider | Update `db-admin-user`/`db-admin-pass` GSM versions; re-run |
| `mysql-app-catalog` JSON malformed | `jsondecode` fails at plan | Don't allow manual edits — only firebase-cloud terraform writes. Documented |
| OCI MySQL is at free-tier downtime | MySQL provider can't connect | Out of scope. `mysql-keepalive.tf` already mitigates the most common cause |
| OCI tfstate S3-compat creds rotated | `terraform init` fails | Re-rotate Customer Secret Key, update `oci-tf-aws-*` GSM versions |
| Catalog version detection false-positive | Dispatch fires on no-op change | Wasted ~1 min; design accepts this (see "unconditional dispatch" decision) |

**Concurrency**: Two firebase-cloud applies in flight queue via terraform state lock; same for personal-cloud. End state converges. No special handling.

**Secret-version churn**: `random_password.app` is `for_each`-keyed by app name. Existing keys keep their generated value across applies. New apps generate version 1 once.

**Operator debug story** (this is the explicit driver for the credential migration):
```
gcloud secrets versions access latest --secret=mysql-app-catalog --project=firebase-cloud-491613
gcloud secrets versions access latest --secret=db-admin-user
gcloud secrets versions access latest --secret=shehryar-db-pass
```
…all return real values, no human-in-the-loop required for diagnosis.

## Migration plan

### Phase 0: Pre-flight verification (no changes)

```
gcloud secrets versions list mysql-app-catalog --project=firebase-cloud-491613   # expect 404
gcloud secrets versions list db-admin-user                                        # expect version 1, populated
oci iam customer-secret-key list --user-id <USER_OCID>                            # confirm 2025 key ACTIVE
gh secret list --repo poly-glot/personal-cloud                                    # snapshot current state
gh secret list --repo poly-glot/firebase-cloud                                    # snapshot current state
```

Capture: personal-cloud deploy SA email (the value behind `INFRA_GCP_SA_EMAIL`).

### Phase 1: Credential migration (one-time bootstrap)

OCI Customer Secret Keys are write-once — you cannot read existing key values back from OCI. Choose:

- **(1a) Recommended**: Delete the 2023 OCI key (after confirming no other workflow consumes it via grep), create a fresh key, capture both halves at creation time, write to GSM:
  ```
  echo -n "<new-access-key-id>"     | gcloud secrets create oci-tf-aws-access-key-id     --data-file=- --replication-policy=automatic --project=firebase-cloud-491613
  echo -n "<new-secret-access-key>" | gcloud secrets create oci-tf-aws-secret-access-key --data-file=- --replication-policy=automatic --project=firebase-cloud-491613
  ```
  Also temporarily update both repos' GitHub `AWS_ACCESS_KEY_ID`/`SECRET` to the new value so existing pre-migration workflow runs still work until phase 4 deletes them.
- **(1b) Fallback**: If you have the existing 2023 key value stored elsewhere (password manager), copy it into GSM. No rotation needed.

Then bootstrap-grant the deploy SA reader access (will be terraform-managed in phase 2):
```
for s in oci-tf-aws-access-key-id oci-tf-aws-secret-access-key db-admin-user db-admin-pass; do
  gcloud secrets add-iam-policy-binding $s \
    --member=serviceAccount:$DEPLOY_SA \
    --role=roles/secretmanager.secretAccessor \
    --project=firebase-cloud-491613
done
```

Verify: from a shell impersonating the deploy SA, `gcloud secrets versions access latest --secret=oci-tf-aws-access-key-id` returns the value.

### Phase 2: firebase-cloud code change + apply

1. Create `terraform/modules/app-with-mysql/{main.tf,variables.tf,outputs.tf}`.
2. Modify `terraform/apps/shehryar.tf`: remove the 3 `google_secret_manager_secret` blocks (`:61-83`), add `module "shehryar_db"`.
3. Create `terraform/apps/mysql-catalog.tf` (locals + secret + version + 5 IAM bindings).
4. Add `variable "personal_cloud_deploy_sa"` to `terraform/variables.tf`; set its value in tfvars.
5. **terraform state import** the existing GCP shells into the new module addresses:
   ```
   terraform import 'module.shehryar_db.google_secret_manager_secret.shells["user"]' projects/firebase-cloud-491613/secrets/shehryar-db-user
   terraform import 'module.shehryar_db.google_secret_manager_secret.shells["pass"]' projects/firebase-cloud-491613/secrets/shehryar-db-pass
   terraform import 'module.shehryar_db.google_secret_manager_secret.shells["name"]' projects/firebase-cloud-491613/secrets/shehryar-db-name
   ```
   (Exact resource address depends on module implementation — confirm in the implementation plan.)
6. Add `MYSQL_APPS_DISPATCH_TOKEN` GitHub secret on `poly-glot/firebase-cloud` (fine-grained PAT, `actions:write` on `poly-glot/personal-cloud` only).
7. Modify `.github/workflows/terraform.yml`: add post-apply dispatch step.
8. Push, watch firebase-cloud apply: plan should be "create SA, create IAM bindings, create catalog secret + version, refactor shell ownership via imports" — no destroys, no drift.
9. Verify: `shehryar-runtime@...` SA exists (`gcloud iam service-accounts list`), 4 IAM bindings on shells exist (`gcloud secrets get-iam-policy shehryar-db-user`), `mysql-app-catalog` v1 contains valid JSON (`gcloud secrets versions access latest --secret=mysql-app-catalog | jq .`).

### Phase 3: personal-cloud code change + state cleanup + apply

1. Modify `06-mysql-apps/data.tf`, `apps.tf`, `variables.tf`, `.github/workflows/terraform-mysql-apps.yaml` per Components section.
2. Modify `.github/workflows/terraform-mysql-heatwave.yaml` to use `get-secretmanager-secrets` for MySQL admin creds + AWS tfstate creds.
3. **terraform state rm** the now-orphaned resources from personal-cloud state:
   ```
   terraform state rm 'google_secret_manager_secret.app_user["shehryar"]'
   terraform state rm 'google_secret_manager_secret.app_pass["shehryar"]'
   terraform state rm 'google_secret_manager_secret.app_name["shehryar"]'
   terraform state rm 'google_secret_manager_secret_version.app_user["shehryar"]'
   terraform state rm 'google_secret_manager_secret_version.app_pass["shehryar"]'
   terraform state rm 'google_secret_manager_secret_version.app_name["shehryar"]'
   terraform state rm 'google_secret_manager_secret_iam_member.app_access'   # entire map; was never fully created
   ```
   `random_password.app["shehryar"]` STAYS in state — its value populates the new versions.
4. Push. personal-cloud apply plan should show:
   - Reads catalog data source
   - Reads 3 shell data sources (now owned by firebase-cloud)
   - Creates `mysql_database "rn_chatapp"`, `mysql_user "shehryar"`, `mysql_grant`
   - Creates new `secret_version` on the 3 shells (using existing `random_password` value)
   - No destroys
5. Verify: `shehryar-db-pass` has version ≥ 2 with non-empty data; `SHOW DATABASES;` on MySQL includes `rn_chatapp`; `SELECT user FROM mysql.user` includes `shehryar`.
6. Verify Cloud Run can read: `gcloud run services describe shehryar-api --region=<region> --format='value(spec.template.spec.containers[0].env)'` shows secret refs resolving.

### Phase 4: GitHub-secrets cleanup

Once Phase 3 passes:
```
gh secret delete DB_USER              --repo poly-glot/personal-cloud
gh secret delete DB_PASS              --repo poly-glot/personal-cloud
gh secret delete AWS_ACCESS_KEY_ID    --repo poly-glot/personal-cloud
gh secret delete AWS_SECRET_ACCESS_KEY --repo poly-glot/personal-cloud
gh secret delete DB_USER              --repo poly-glot/firebase-cloud
gh secret delete DB_PASS              --repo poly-glot/firebase-cloud
```

### Phase 5: Smoke-test the add-an-app flow

1. Create `firebase-cloud/terraform/apps/_smoketest.tf` with module call (only identity + db module, no Cloud Run).
2. Push, observe end-to-end: firebase-cloud apply → dispatch → personal-cloud apply → `_smoketest_db` exists in MySQL, `_smoketest-db-pass` has populated version.
3. Roll back via Flow C two-step removal.
4. Confirm: zero manual commands run between push and provisioning.

## Acceptance criteria

- Adding a real new app requires editing one `.tf` file in firebase-cloud + one push. No commands run by hand.
- Removing an app requires two pushes (Flow C / c1) and zero manual commands.
- An operator (or Claude) can run `gcloud secrets versions access latest --secret=<anything>` to debug any future failure.
- `terraform plan` in both repos on `main` shows zero drift after migration.
- No GitHub secrets exist for values that change at runtime — only WIF bootstrap (`INFRA_*`), the cross-repo dispatch PAT, and OCI auth (kept by choice — see scope (II) below).

## Scope decisions

This design intentionally chose **(A) firebase-cloud-only edits** for adding apps, **(i) GSM apps-catalog** for discovery, **(b) auto-dispatch** for triggering personal-cloud, and **(II) pragmatic credential migration** (DB creds + tfstate creds to GSM, leave OCI auth in GitHub).

Out of scope for this design (deferred or explicitly rejected):
- Migrating OCI auth credentials to GSM (rare rotation; not the source of debugging pain).
- Renaming an existing database (Flow B — destructive, would lose data; do manually if ever needed).
- Single-step app removal (Flow C — chosen two-step for safety; one-step needs lifecycle ordering across repos which is fragile).
- Eliminating the `production` environment gate on firebase-cloud (you may want manual approval; design works either way).

## Open risks

- **2023 OCI Customer Secret Key may be referenced elsewhere.** Mitigation: phase 1 keeps GitHub `AWS_*` secrets temporarily updated to the new key value; only delete after a grace period and a `git grep AWS_ACCESS_KEY_ID` across both repos confirms no other workflow consumes them.
- **Module address for shell imports** in phase 2 step 5 depends on the module's internal resource naming. The implementation plan must specify the exact `terraform import` addresses after the module is written.
