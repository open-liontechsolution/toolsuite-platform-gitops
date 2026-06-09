# Longhorn (Helm Chart wrapper)

This component deploys [Longhorn](https://longhorn.io) using the official
[Longhorn Helm chart](https://charts.longhorn.io) as a dependency. Deploy this **once per cluster**,
not per environment. It mirrors the `apps/platform/cert-manager/` pattern (wrapper chart + ArgoCD
Application).

> **Why this exists:** Longhorn was the only core-stack component **not** in GitOps — it ran as a raw
> `helm install` (`longhorn-1.7.1`, release rev 2), outside Git and outside ArgoCD. The 1.7.x line is
> **EOL** (2025-09-04) and does not support Kubernetes 1.33, yet the cluster is already on k8s 1.33.
> This wrapper adopts the live release at 1.7.1 (inert diff) so the off-EOL upgrade chain can then run
> through GitOps, one minor per commit.

The **backup target** (`s3://longhorn-backup@us-east-1/`, credential secret `minio-secret`) and the
**RecurringJobs** (snapshots/backups) are configured as Longhorn `Setting`/`RecurringJob` CRs
**out-of-band** (not via Helm). They are intentionally NOT declared in `values.yaml` — pinning them
would change ownership and break the inert adoption. They remain live, untouched.

## Layout

```text
apps/platform/longhorn/
├── Chart.yaml                 # wrapper chart; pins the longhorn dependency version
├── values.yaml                # config under the `longhorn:` subchart key
├── README.md
└── argocd/
    └── longhorn.yaml           # ArgoCD Application (release name == longhorn, prune disabled)
```

> `Chart.lock` and `charts/` are git-ignored (repo-wide). Run `helm dependency build` locally before
> rendering; the output is not committed.

## Version chain (off-EOL, one minor at a time)

Longhorn enforces **consecutive-minor upgrades only** (since v1.5) — skipping a minor fails
automatically, and from 1.10 a pre-upgrade validation job blocks unsupported paths. The cluster is on
**k8s 1.33**; Longhorn **1.9.x is the lowest line that supports k8s 1.33**, so getting off 1.7 is the
priority. Target line: **v1.11.2** (mature, covers k8s 1.32–1.35).

| Step       | Longhorn | chart  | k8s tested | Notes |
|------------|----------|--------|-----------|-------|
| Adoption   | v1.7.1 (= live, inert diff) | 1.7.1 | ≤1.28 | runs on k8s 1.33 = **out of support**, urgent |
| 1          | v1.8.2   | 1.8.2  | ≤1.31     | transiently on k8s 1.33 (unavoidable: consecutive-minor rule) |
| 2          | v1.9.2   | 1.9.2  | 1.30–1.33 | **first line that supports k8s 1.33** |
| 3          | v1.10.2  | 1.10.2 | 1.30–1.33 | **no downgrade after 1.10**; ensure CRDs migrated off v1beta1 first (longhorn#11886) |
| 4 (target) | v1.11.2  | 1.11.2 | 1.32–1.35 | target |

The Longhorn chart version equals the release version without the leading `v`. Re-check the latest
patch of each minor at <https://github.com/longhorn/longhorn/releases> before each hop.

## Adoption of the existing (raw Helm) install — run ONCE

Unlike cert-manager (which was an orphan **ArgoCD** Application), Longhorn currently runs as a raw
**Helm release** — there is no ArgoCD Application to delete. ArgoCD adopts the Helm-managed resources
in place via a matching `releaseName: longhorn` + `ServerSideApply=true`. The Application pins 1.7.1,
so the desired-state recompute is inert (no pod/CRD/volume churn).

> ⚠️ **Never cascade-delete this Application.** The `resources-finalizer` would tear down the Longhorn
> workload **and its CRDs**, destroying every Volume/Replica in the cluster. If you ever remove it, do
> it **non-cascaded** (`--cascade=orphan`) so the live resources survive.
>
> ⚠️ **`prune` is disabled** in the Application on purpose. Longhorn creates runtime CRs (Volumes,
> Engines, Replicas, Settings, Nodes) that are not in the chart's rendered manifests; prune could try
> to delete them. Keep `prune: false` for this storage component.

```bash
export KUBECONFIG=~/.kube/k3slocal.yaml

# 0. Confirm Longhorn is a raw Helm release (not an ArgoCD app) and capture the baseline.
kubectl -n argocd get applications | grep -i longhorn || echo "no longhorn ArgoCD app (expected)"
kubectl -n longhorn-system get ds longhorn-manager -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'  # longhornio/longhorn-manager:v1.7.1
kubectl -n longhorn-system get volumes.longhorn.io -o custom-columns=N:.metadata.name,S:.status.state,R:.status.robustness

# 1. Build deps and confirm the rendered manifest matches what is live (INERT diff).
cd apps/platform/longhorn
helm dependency build
helm template longhorn . -n longhorn-system | kubectl diff -f - || true
# Expect: same resource names, no recreation; at most tracking labels/annotations.

# 2. Apply the Application — ArgoCD adopts the Helm-managed resources in place.
kubectl apply -f apps/platform/longhorn/argocd/longhorn.yaml

# 3. Verify adoption with NO churn.
kubectl -n argocd get application longhorn -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'
kubectl -n longhorn-system get ds longhorn-manager -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'  # still v1.7.1
kubectl -n longhorn-system get pods            # high AGE, no mass restarts
kubectl -n longhorn-system get volumes.longhorn.io -o custom-columns=N:.metadata.name,S:.status.state,R:.status.robustness
```

**Go/No-Go (adoption):** Application `Synced/Healthy` + manager image still `v1.7.1` + no pod churn +
volumes still `attached/healthy`.

## Version bumps (after adoption) — GitOps, one minor per commit

ArgoCD reads `targetRevision: main` with `automated` + `selfHeal`, so each hop is a commit to `main`:

1. Edit `Chart.yaml`: bump the dependency `version` and `appVersion` to the next minor (see table).
2. `helm dependency build` (local sanity render), commit, merge to `main` → ArgoCD auto-syncs.
3. Per hop, follow the runbook below, then validate (Go/No-Go) before the next hop. Note: **downgrade is
   not possible from 1.10 onward** — there is no rollback once past it, so validate carefully.

### Per-hop runbook
```bash
export KUBECONFIG=~/.kube/k3slocal.yaml

# a. Back up Longhorn CRDs before the hop.
kubectl get volumes.longhorn.io,engines.longhorn.io,replicas.longhorn.io,settings.longhorn.io,nodes.longhorn.io \
  -A -o yaml > longhorn-crds-backup-$(date +%F).yaml

# b. The pre-upgrade checker job (preUpgradeChecker.jobEnabled: true) runs on sync — if it fails, STOP.
# c. Wait for manager / instance-manager / CSI pods Ready and reconciled.
kubectl -n longhorn-system get pods
kubectl -n longhorn-system get settings.longhorn.io current-longhorn-version -o jsonpath='{.value}{"\n"}'

# d. Engine images do NOT auto-upgrade (concurrent-automatic-engine-upgrade-per-node-limit: 0).
#    Upgrade each volume's engine image to the new default via the Longhorn UI (or bump the setting).
kubectl -n longhorn-system get engineimages.longhorn.io

# e. Validate.
kubectl -n longhorn-system get volumes.longhorn.io -o custom-columns=N:.metadata.name,S:.status.state,R:.status.robustness
kubectl get pvc -A | grep -v Bound || echo "all PVCs Bound"
kubectl get sc | grep longhorn      # StorageClass 'longhorn' still default
kubectl -n argocd get application longhorn -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'
```

**Go/No-Go per hop:** pods Running + volumes `attached/healthy` + app PVCs `Bound` + engine images on
the target version + Application `Synced/Healthy`.

### Gotchas
- **No downgrade after 1.10** — validate each hop before proceeding; there is no rollback.
- **CRD `v1beta1` → `v1beta2`**: ensure stored CRDs are migrated before crossing 1.9 → 1.10
  (known upgrade failure, longhorn#11886). The cluster already reports `crd-api-version: longhorn.io/v1beta2`.
- **`worker5` is cordoned** (`SchedulingDisabled`) — with `defaultClassReplicaCount: 3` most volumes
  still replicate elsewhere, but account for it during node drains/rebuilds.
- **`block-for-eviction-if-contains-last-replica`** is already the live `node-drain-policy` — safe drains.
- **ServiceMonitors** for Longhorn metrics live in the external `k3s-local-apps-manifests` repo and may
  change endpoints between versions; re-verify metrics after the final hop.
- **`backup-target`** (MinIO S3) and **RecurringJobs** are managed out-of-band and already configured —
  do not move them into `values.yaml`.
