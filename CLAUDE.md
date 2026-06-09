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
  `environments/{local,cloud}/{dev,qa,prod}.yaml`, and each has its own Application under
  `argocd/clusters/{local,cloud}/{env}.yaml`.

**Deployment order is a hard dependency:** the CNPG operator (and its CRDs) must exist before any CNPG
cluster syncs. Same for cert-manager before any Certificate/Issuer consumer.

## Environment & namespace model

`{local|cloud}` (deployment target) × `{dev|qa|prod}` (tier) is selected purely by which env values file
an Application references — the architecture does not change between them. Each tier maps to its own
namespace (`data-dev` / `data-qa` / `data-prod`, `security-dev`, etc.), so multiple environments can
coexist in one cluster with RBAC isolation. `local` targets k3s + Longhorn storage; `cloud` targets
cloud storage classes with larger replica counts/resources.

## Secrets: Sealed Secrets, committed encrypted

Secrets are **not** plain Kubernetes Secrets. Each chart's `templates/sealedsecret.yaml` renders a
Bitnami `SealedSecret` (gated on `sealedSecret.enabled`), and the encrypted ciphertext lives directly in
the environment values file (e.g. `apps/data/cnpg/environments/local/dev.yaml`). These encrypted values
are safe to commit; the in-cluster sealed-secrets controller unseals them.

Encrypt a value with kubeseal (namespace and secret name are part of the encryption — they must match the
deployment target exactly):

```bash
echo -n "your-value" | kubeseal --raw --from-file=/dev/stdin \
  --namespace data-dev --name platform-postgres-app
```

Then paste the output under `sealedSecret.encryptedData.<field>` in that environment's values file.
The legacy `environments/local/secrets/` directories are deprecated reference material — do not add new
secrets there.

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
- **`keycloak/templates/cloudflared.yaml` is intentionally empty** — cloudflared runs as a sidecar via
  `keycloakx.extraContainers`, not as a separate manifest. Don't "fix" it by adding a Deployment.
- Affinity rules in CNPG env values deliberately target worker nodes labelled `performance=high`; the
  comments explain why the worker label is required (to exclude a control-plane node carrying the same
  performance label).
- Argo CD Applications use `ignoreDifferences` to suppress noisy diffs (CRD `caBundle`, CNPG
  `/status`, Keycloak StatefulSet `/spec/replicas`). Preserve these when editing Applications.

## Docs map

`docs/guides/deployment.md` (step-by-step), `docs/guides/troubleshooting.md`,
`docs/SEALED-SECRETS-GUIDE.md`, and `docs/migration/*` (history of the Kustomize→Helm migration and
structure reorganizations).
