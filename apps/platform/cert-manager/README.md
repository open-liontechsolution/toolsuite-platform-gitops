# cert-manager (Helm Chart wrapper)

This component deploys [cert-manager](https://cert-manager.io) using the official
[Jetstack Helm chart](https://charts.jetstack.io) as a dependency. Deploy this **once per cluster**,
not per environment. It mirrors the `apps/platform/cnpg-operator/` pattern (wrapper chart + ArgoCD
Application).

The **ClusterIssuers** (staging/prod) are NOT managed here — they live in `k3s-local-apps-manifests/cert-manager/`
(kubectl-applied) and are consumers of this component.

## Layout

```text
apps/platform/cert-manager/
├── Chart.yaml                 # wrapper chart; pins the cert-manager dependency version
├── values.yaml                # config under the `cert-manager:` subchart key
├── README.md
└── argocd/
    └── cert-manager.yaml       # ArgoCD Application (release name == cert-manager)
```

> `Chart.lock` and `charts/` are git-ignored (repo-wide). Run `helm dependency build` locally before
> rendering; the output is not committed.

## Version chain (k8s 1.33 gate)

cert-manager `v1.16.x` tops out at k8s 1.32. To allow the cluster upgrade to k8s 1.33 we step up one
minor at a time, landing on the non-EOL `v1.19.x` line (covers k8s 1.31–1.35):

| Step      | cert-manager | k8s supported |
|-----------|--------------|---------------|
| Adoption  | v1.16.1 (= live, inert diff) | 1.25–1.32 |
| 1         | v1.17.4      | 1.29–1.33 |
| 2         | v1.18.6      | 1.29–1.33 |
| 3 (target)| v1.19.5      | 1.31–1.35 |

The Jetstack chart version equals the cert-manager release version. Re-check the latest patch of each
minor at <https://cert-manager.io/docs/releases/> before each hop.

## Adoption of the existing (orphan) install — run ONCE

cert-manager already runs in the cluster as an **orphan ArgoCD Application** sourced directly from the
Jetstack chart (not declared in git). We adopt it into this repo at the **current live version (v1.16.1)**
first, so the desired-state recompute is inert and there is no churn of cluster-scoped CRDs.

> ⚠️ **Do not cascade-delete the orphan Application.** ArgoCD's `resources-finalizer` would also delete
> the cert-manager workload **and its CRDs** (breaking every Certificate/Issuer in the cluster). If you
> remove the old Application, do it **non-cascaded** so the live resources survive and the new Application
> adopts them.

```bash
export KUBECONFIG=~/.kube/k3slocal.yaml

# 0. Inspect the current Application(s) and confirm the orphan's exact name.
kubectl -n argocd get applications

# 1. Build deps and confirm the rendered manifest matches what is live (INERT diff).
cd apps/platform/cert-manager
helm dependency build
helm template cert-manager . -n cert-manager | kubectl diff -f - || true
# Expect: same resource names (cert-manager / -webhook / -cainjector), no recreation.

# 2a. PREFERRED — remove the old orphan Application WITHOUT touching the workload, then apply ours:
kubectl -n argocd delete application <orphan-name> --cascade=orphan
# (if it hangs on the finalizer:
#   kubectl -n argocd patch application <orphan-name> -p '{"metadata":{"finalizers":null}}' --type merge
#   kubectl -n argocd delete application <orphan-name> --cascade=orphan )
kubectl apply -f apps/platform/cert-manager/argocd/cert-manager.yaml

# 2b. ALTERNATIVE — if the orphan is already named `cert-manager`, applying ours overwrites its spec
#     in place (no delete needed):
# kubectl apply -f apps/platform/cert-manager/argocd/cert-manager.yaml

# 3. Verify adoption with NO pod churn.
kubectl -n argocd get application cert-manager -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'
kubectl get pods -n cert-manager
```

## Version bumps (after adoption) — GitOps, one minor per commit

ArgoCD reads `targetRevision: main` with `automated` + `selfHeal`, so each hop is just a commit to `main`:

1. Edit `Chart.yaml`: bump the dependency `version` and `appVersion`.
2. On the **first** hop, migrate `values.yaml` `installCRDs: true` → `crds: { enabled: true, keep: true }`.
3. `helm dependency build` (local sanity render), commit, merge to `main` → ArgoCD auto-syncs.
4. Validate (Go/No-Go) before the next hop. If it fails, revert the commit (ArgoCD reverts).

## Validation (per hop and final)

```bash
export KUBECONFIG=~/.kube/k3slocal.yaml
kubectl get deploy -n cert-manager -o jsonpath='{range .items[*]}{.metadata.name}={..image}{"\n"}{end}'
kubectl get pods -n cert-manager           # 3 deploys Running, webhook Ready
kubectl get crd | grep cert-manager.io     # CRDs served
kubectl -n argocd get application cert-manager -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'
# Smoke test: create a test Certificate against an existing ClusterIssuer and confirm it goes Ready.
```

**Go/No-Go per hop:** pods Running + webhook Ready + Application Synced/Healthy + test Certificate Ready.
