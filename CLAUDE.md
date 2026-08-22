# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A GitOps repository (no application source code) that bootstraps a local-first, cloud-ready Kubernetes
platform. Everything is declarative: **Helm wrapper charts** rendered and reconciled by **Argo CD**.
There is no build step, no CI workflow, and no test framework — validation is done by rendering charts
locally and letting Argo CD reconcile against the cluster.

## Core architectural pattern: wrapper chart + Argo CD Application

Every component under `apps/` follows the same two-part shape:

1. A **wrapper Helm chart** (`Chart.yaml` + `values.yaml`) that declares the official upstream chart as
   a *dependency* and pins its version. Local config lives under the subchart's top-level key (e.g.
   `cluster:`, `cert-manager:`, `keycloakx:`). The wrapper adds repo-specific templates under
   `templates/` (most commonly a `SealedSecret`).
2. One or more **Argo CD `Application` manifests** under the chart's `argocd/` directory pointing at the
   chart `path`, the env values files, and a target namespace.

`Chart.lock` and `charts/` are **git-ignored repo-wide** (see `.gitignore`). They are build artifacts —
run `helm dependency build` locally before rendering; never commit them.

### Two component tiers (this distinction matters)

- **Platform / operators** (`apps/platform/*`: `cnpg-operator`, `cert-manager`): deployed **once per
  cluster**, into a single namespace, under Argo CD project `default`. One Application, no per-env values.
- **Workloads** (`apps/data/cnpg`, `apps/security/keycloak`): deployed **once per environment**, under
  Argo CD project `tools`. The base `values.yaml` is shared; each environment layers a values file from
  `environments/{target}/{env}.yaml`, and each has its own Application under
  `argocd/clusters/{target}/{env}.yaml`. Only the combinations that exist are committed — see below.

**Deployment order is a hard dependency:** the CNPG operator (and its CRDs) must exist before any CNPG
cluster syncs. Same for cert-manager before any Certificate/Issuer consumer.

## Environment & namespace model

`{local|cloud}` (deployment target) × `{dev|qa|prod|casa}` (tier) is selected purely by which env values
file an Application references — the architecture does not change between them. Each tier maps to its own
namespace, so multiple environments coexist in one cluster with RBAC isolation. `local` targets k3s +
Longhorn storage; `cloud` targets cloud storage classes with larger replica counts/resources.

**The matrix is aspirational — check what actually exists before assuming.** Live namespaces today:
`data-dev`, `data-casa`, `security-dev`, `security-casa`, plus `data-prod` and `security-prod` added by
issue #62 — and those two hold **only the production Keycloak and its database**, nothing else. There
is still **no** `data-qa`, and no `cloud` deployment at all; `apps/data/cnpg` had values and
Applications for all of them and they were deleted in issue #44 (they had never worked — see below).
`casa` is a fourth tier, not part of dev/qa/prod: the family/home tools (`authentik-postgres-casa`,
Authentik). Note the asymmetry `data-prod` creates: `deal_tracker_prod`, the application's own
production database, still lives in `platform-postgres-dev` under `data-dev`. Only the IdP moved.

**Env values nest one level deeper than they look.** In a wrapper chart the subchart's own `cluster`
section is at `cluster.cluster.*`, not `cluster.*` — the first key is the subchart name in the wrapper.
Getting this wrong is silent: Helm accepts the file, the subchart ignores it, the resource renders with
upstream defaults. Five values files in `apps/data/cnpg` sat broken this way for months. When editing an
env values file, render it and confirm the field actually moved.

## Secrets: Sealed Secrets, committed encrypted

Secrets are **not** plain Kubernetes Secrets. Each chart's `templates/sealedsecret.yaml` renders a
Bitnami `SealedSecret` (gated on `sealedSecret.enabled`), and the encrypted ciphertext lives directly in
the environment values file (e.g. `apps/data/cnpg/environments/local/dev.yaml`). These encrypted values
are safe to commit; the in-cluster sealed-secrets controller unseals them.

Encrypt a value with kubeseal (namespace and secret name are part of the encryption — they must match the
deployment target exactly):

```bash
echo -n "your-value" | kubeseal --raw --from-file=/dev/stdin \
  --namespace data-dev --name platform-postgres-app \
  --controller-name sealed-secrets --controller-namespace kube-system
```

Then paste the output under `sealedSecret.encryptedData.<field>` in that environment's values file.
Some charts render more than one SealedSecret from more than one values block — `apps/data/cnpg` has
`sealedSecret` (DB credentials) and `backupSecret` (the S3 credential for backups), each with its own
template. Do not add new secrets to `environments/local/secrets/`; that pattern is gone.

The same plaintext used in two namespaces must be sealed **twice**, once per namespace — the ciphertexts
differ. That is why the MinIO backup credential appears in both `apps/data/cnpg` (`data-dev`) and
`apps/data/authentik-postgres` (`data-casa`), and why the Keycloak DB password is sealed once for
`data-prod` and again for `security-prod`.

A ciphertext sealed against the wrong namespace looks exactly like a good one and fails late — the
SealedSecret applies without complaint and the `Secret` simply never appears. Ask the controller
first: render **only** the SealedSecret templates (`-s`), with the destination `--namespace`, and pipe
that into `kubeseal --validate`; silence means valid. Both flags are load-bearing — without `-s` the
request is rejected outright, and without `--namespace` every SealedSecret renders as `default` and
fails validation in false, including ones live in the cluster. Worked example and the third failure
mode: `docs/SEALED-SECRETS-GUIDE.md`.

## Common commands

```bash
# Render a chart locally to inspect output (always pulls deps first)
cd apps/data/cnpg
helm dependency build
helm template platform-postgres-dev . -f values.yaml -f environments/local/dev.yaml

# Lint a chart
helm lint apps/data/cnpg -f apps/data/cnpg/values.yaml -f apps/data/cnpg/environments/local/dev.yaml

# Deploy a platform operator directly (once per cluster)
helm upgrade --install cnpg-operator apps/platform/cnpg-operator \
  -n cnpg-system --create-namespace -f apps/platform/cnpg-operator/values.yaml

# GitOps deploy (preferred): apply the Argo CD Application, let it reconcile
kubectl apply -f apps/data/cnpg/argocd/clusters/local/dev.yaml
argocd app sync cnpg-cluster-local-dev
```

Note the Argo CD `Application` name (`metadata.name`) often differs from the Helm `releaseName` — e.g.
Application `cnpg-cluster-local-dev` deploys Helm release `platform-postgres-dev`. The `releaseName` is
load-bearing: it must match the live release so resources keep their existing names instead of being
duplicated and pruned.

## Conventions worth knowing before editing

- **Upgrading an upstream chart** = bump the version in *both* `Chart.yaml` (`dependencies[].version`,
  often `appVersion` too) and reconcile. cert-manager upgrades follow a deliberate **one-minor-at-a-time
  hop strategy** gated on the target Kubernetes version — read `apps/platform/cert-manager/README.md`
  before touching its version; the recent git history is exactly these staged hops.
- **There are two Keycloak instances, and the directory decides which realm each one gets.** Since
  issue #62 production is isolated: `security-prod` / release `keycloak-prod`, its own CNPG cluster
  (`apps/data/keycloak-postgres` in `data-prod`), its own host `keycloak.liontechsolution.com` served
  by the **k3s-prod** tunnel. `security-dev` keeps dev and QA — QA authenticates against the
  `deal-tracker-dev` realm, it has no instance of its own. The split is `realmConfig.path`:
  `realms/nonprod` for the dev instance, `realms/prod` for production. The ConfigMap glob does not
  descend into subdirectories, so neither instance can import the other's realm — and a realm file
  dropped in `realms/` itself is deployed nowhere and fails the render. Anything reaching into one
  of them (`scripts/keycloak-user.sh`, `keycloak-client-secret.sh`) defaults to the dev pod and
  needs `KC_NS=security-prod KC_POD=keycloak-prod-0` for production; pointing at the wrong one
  reports the realm as nonexistent, not as a wrong target.
- **Realms and clients are declared in git; people deliberately are not.** `keycloak-config-cli`
  applies each instance's `realms/` subdirectory (PostSync Job + a nightly reconcile CronJob with
  the checksum cache off). Users stay out for a reason that is easy to get backwards: config-cli
  cannot purge them, and that same nightly reconcile would re-enable anyone you had disabled, so a
  declared user could never be offboarded. They are managed with `scripts/keycloak-user.sh`
  (`crear`/`listar`/`reset`/`baja`), which hands out a **temporary** password and forces
  `UPDATE_PASSWORD`. Manual signup is the policy, not a gap, and it stays one now that SMTP exists:
  none of the three reasons users are undeclarable depended on email. Reasoning:
  `docs/KEYCLOAK_USERS.md`.
- **The realms do have SMTP now** (Resend, issue #60), with `resetPasswordAllowed`, `verifyEmail`
  and a `passwordPolicy` — `registrationAllowed` stays `false` because signup is by invitation, not
  because email is missing. Three traps: the SMTP password is **not** in `realms/` but comes in by
  var-substitution (`$(env:…)`, prefix `$(` not `${`, enabled by `realmConfig.varSubstitution`), and
  a **missing variable aborts the import of both realms**, not just its own; there is **one key per
  realm** because each sends from its own verified domain; and the egress NetworkPolicy rule for
  port 587 (`networkPolicy.smtp`) is the **only rule in that policy that actually reaches the
  internet** — the others use `namespaceSelector`, which only ever matches in-cluster pods, so
  adding a port there does nothing. Without it Keycloak sends no mail and the symptom reads as "it
  doesn't arrive", not as a blocked socket.
  **The one `users:` block in `realms/` is a service account, not a person** — config-cli can only
  assign a service account's role through a `users:` entry with `serviceAccountClientId`; it is not
  a client field. Only service accounts go there. Two traps with the confidential client that owns
  it (`deal-tracker-api`): without `fullScopeAllowed: true` the Admin API returns **403 with the
  role correctly assigned**, because authorization reads `resource_access.realm-management.roles`
  from the *token*, not the user's mapping; and its **secret is never declared** — Keycloak
  generates it and config-cli leaves it alone (with `secret` absent, `isClientEqual` returns true
  without consulting it), so the nightly job does not rotate it. Extract it with
  `scripts/keycloak-client-secret.sh` and seal it in `k3s-local-apps-manifests`.
- **Neither Keycloak instance ships cloudflared, and neither should.** That template is gone: both
  hosts are served by cluster-wide shared tunnels that live outside this repo — `k3s-nonprod`
  (ns `cloudflared`) for `keycloak-dev`, `k3s-prod` (ns `cloudflared-prod`) for `keycloak`. The
  routing table is not in either tunnel's ConfigMap either: they are remotely-managed, so publishing
  a host means adding a Public Hostname in Cloudflare Zero Trust pointing at the internal Service.
  Don't "fix" a missing host by adding a sidecar or a Deployment here.
- Affinity rules in CNPG env values deliberately target worker nodes labelled `performance=high`; the
  comments explain why the worker label is required (to exclude a control-plane node carrying the same
  performance label). **`worker4` is currently the only worker with that label**, which is why both CNPG
  clusters run `instances: 1` — raising it without relabelling a node or relaxing the affinity leaves the
  second pod `Pending`.
- Argo CD Applications use `ignoreDifferences` to suppress noisy diffs (CRD `caBundle`, CNPG
  `/status`, Keycloak StatefulSet `/spec/replicas`). Preserve these when editing Applications.
- **`cnpg-cluster-local-dev` has no `automated` sync policy on purpose** — several published apps depend
  on the databases in `platform-postgres-dev`, so an auto-sync with `prune`/`selfHeal` would push any repo
  mistake straight at them. After merging a change under `apps/data/cnpg` the Application stays
  `OutOfSync` until someone syncs it by hand (`argocd app sync cnpg-cluster-local-dev`, or
  `kubectl -n argocd patch app … -p '{"operation":{"sync":{}}}'`). Do not "fix" it by adding `automated`.
  `authentik-postgres-local-casa` does sync automatically — the two policies differ deliberately.
  **`keycloak-local-dev` and `cnpg-operator` are manual too**, each for its own reason (realms reaching
  the IdP unreviewed; `prune` on a CRD taking every `Cluster` of that kind with it) — both written out
  in the `syncPolicy` comment of their Application. Auto-sync is the exception here, not the default.
- **Applications are applied by hand and nothing reconciles the file against the live object.** There is
  no app-of-apps, so a change made in the cluster and never brought down to git sits there silently until
  someone re-applies the file — and then lands all at once. Two Applications diverged that way for months
  (issue #65). Check with `scripts/argocd-drift.sh`. Do not compare them with a plain `diff`: the API
  server strips zero-values on write (`allowEmpty: false`, `prune: false`, `group: ""`), so a raw
  comparison flags 6 of the 8 Applications in false — the script normalises that first.
- **Monitoring objects for CNPG are owned by the `k3s-local-apps-manifests` repo**, not this one. Its
  `prometheus/cnpg/podmonitor.yaml` declares the PodMonitor (ns `monitoring`, `namespaceSelector` over
  `data-dev` + `data-casa`) and `prometheus/prometheus/rules-cnpg.yaml` the alert rules. Keep
  `cluster.monitoring.podMonitor.enabled` and `.prometheusRule.enabled` **false** in both CNPG charts:
  the first would duplicate the scrape, and the second emits rules without the
  `prometheus: prometheus-persistant` label, which our `ruleSelector` drops silently. Taking ownership
  means deleting the object there first, then enabling it here — in that order.
- **Databases and roles inside a CNPG cluster are declarable, and the nesting is asymmetric.** Since
  operator 1.25 the `Database` CRD and `spec.managed.roles` do this natively — no Job, no CronJob. In
  the wrapper: databases go in **`cluster.databases`** (a sibling of `cluster.cluster`, *outside* it),
  roles go in **`cluster.cluster.roles`** (*inside*; the subchart builds the `managed:` block itself).
  `cluster.managed.roles`, the intuitive spelling, renders without the role and says nothing. Role
  passwords need `templates/role-sealedsecret.yaml`, not the `sealedSecret` block — CNPG requires
  `type: kubernetes.io/basic-auth` and matches the secret's `username` against the role name.
  Two traps worth knowing before touching this: declaring a role that **already exists** with a
  `passwordSecret` makes CNPG **reset its password** to the sealed one (adopt preexisting roles one at
  a time, never in a batch), and Argo owns `spec.managed.roles` as an **atomic list**, so the
  API-server defaults inside it (`inherit`, `connectionLimit`) must be written out or the Application
  sits `OutOfSync` forever. `platform-postgres-dev` still has **five databases created by hand** that
  live in no repo — `apps/data/cnpg/README.md` has the inventory and the procedure.
- **Postgres backups are `barmanObjectStore` → MinIO** (`s3://cnpg-backup`), configured in the base
  `values.yaml` of `apps/data/cnpg` and `apps/data/authentik-postgres`, switched on per environment. The
  in-tree barman support is deprecated and disappears in CNPG **1.31** (operator is on 1.28.1); migrating
  to the `barman-cloud` CNPG-I plugin is pending. Longhorn volume backups are not a substitute — they
  cover disk loss, not a bad `DELETE`.
- **The MinIO side of those backups lives in `kxs-ansible`, not here** (`roles/minio_creds`,
  `playbooks/minio_creds.yml`, `docs/MINIO_CREDS.md`): bucket, policy, user, and the plaintext in its
  encrypted vault. That playbook also runs kubeseal and drops the four ciphertexts in
  `out/cnpg-backup-s3-creds.yaml` for pasting here. Do not create MinIO credentials by hand — that is
  exactly how `longhorn-backup` cost 49 days of silent backup failure.

## Docs map

`docs/guides/deployment.md` (step-by-step), `docs/guides/troubleshooting.md`,
`docs/SEALED-SECRETS-GUIDE.md`, and `docs/migration/*` (history of the Kustomize→Helm migration and
structure reorganizations).
