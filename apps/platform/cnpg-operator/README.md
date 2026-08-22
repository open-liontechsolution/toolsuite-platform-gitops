# CloudNativePG Operator (Helm Chart)

This component deploys the CloudNativePG operator using the official Helm chart. Deploy this **once per cluster**, not per environment.

## Overview

The operator is deployed cluster-wide and manages PostgreSQL clusters across all namespaces. It uses the official [CloudNativePG Helm chart](https://cloudnative-pg.io/charts/) as a dependency.

## Prerequisites

- Kubernetes cluster (k3s, EKS, GKE, AKS, etc.)
- Helm 3.x installed
- kubectl configured to access the cluster

## Deployment

### Using Helm CLI

First, update Helm dependencies:

```bash
cd apps/platform/cnpg-operator
helm dependency update
```

Then install the operator:

```bash
helm upgrade --install cnpg-operator . \
  --namespace cnpg-system \
  --create-namespace \
  --values values.yaml
```

### Using Argo CD

Create an Argo CD Application:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cnpg-operator
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/open-liontechsolution/toolsuite-platform-gitops
    path: apps/platform/cnpg-operator
    targetRevision: main
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: cnpg-system
  syncPolicy:
    # sin `automated`, a proposito: ver "Sync Policy" mas abajo
    syncOptions:
      - CreateNamespace=true
```

El fichero real es `argocd/operator.yaml`; este ejemplo es una copia recortada. Aplicalo con
`kubectl apply -f apps/platform/cnpg-operator/argocd/operator.yaml`, no copiando de aqui.

## Sync Policy

**Esta Application NO lleva `automated`, y no es un olvido.** El chart trae las CRDs de CNPG, y
`prune: true` sobre una CRD se lleva por delante todos los objetos de ese kind — o sea, los dos
clusters de Postgres (`platform-postgres-dev` y `authentik-postgres-casa`) y con ellos las bases de
las que dependen varias aplicaciones publicadas. No es un evento recuperable con un rollback del repo.

Es el mismo razonamiento que ya lleva escrito `cnpg-cluster-local-dev`, que depende de este operador:
si el cluster tiene ventana de revision manual, el operador que lo gobierna no puede tener menos.

El sync se lanza a mano tras revisar el diff:

```bash
argocd app diff cnpg-operator --local apps/platform/cnpg-operator
argocd app sync cnpg-operator
```

Que el fichero y el objeto vivo sigan coincidiendo lo comprueba `scripts/argocd-drift.sh`; nada lo
reconcilia solo.

## Verification

Check that the operator is running:

```bash
# Check Helm release
helm list -n cnpg-system

# Check operator pods
kubectl get pods -n cnpg-system

# Check CRDs
kubectl get crd | grep cnpg

# Check operator logs
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg
```

Expected CRDs:
- `backups.postgresql.cnpg.io`
- `clusters.postgresql.cnpg.io`
- `poolers.postgresql.cnpg.io`
- `scheduledbackups.postgresql.cnpg.io`

## Configuration

### Cluster-Wide vs Single-Namespace

By default, the operator is deployed cluster-wide (`config.clusterWide: true`). To limit it to a single namespace:

```yaml
cloudnative-pg:
  config:
    clusterWide: false
```

**Note:** Single-namespace mode requires the operator to be installed in the same namespace as the PostgreSQL clusters.

### Monitoring

To enable Prometheus monitoring, update `values.yaml`:

```yaml
cloudnative-pg:
  monitoring:
    podMonitorEnabled: true
    podMonitor:
      enabled: true
      labels:
        prometheus: kube-prometheus
```

### Resource Limits

Adjust operator resources based on cluster size:

```yaml
cloudnative-pg:
  resources:
    limits:
      cpu: 1000m
      memory: 1Gi
    requests:
      cpu: 200m
      memory: 256Mi
```

## Upgrading

To upgrade the operator:

```bash
cd apps/platform/cnpg-operator
helm dependency update
helm upgrade cnpg-operator . \
  --namespace cnpg-system \
  --values values.yaml
```

Or let Argo CD handle it automatically if using GitOps.

## Uninstalling

```bash
helm uninstall cnpg-operator -n cnpg-system
```

**Warning:** This will not delete existing PostgreSQL clusters, but they will no longer be managed.

## Migration History

This chart uses the official CloudNativePG operator Helm chart for deployment. All configuration is managed through the `values.yaml` file.

For historical context on the migration to Helm, see `docs/migration/` in the repository root.

### Version upgrades

- **0.22.0 → 0.27.1** (operator `1.24.0` → `1.28.1`): prerequisite for upgrading k3s from
  1.31 → 1.32 (CNPG 1.24 only supports k8s ≤1.31; the 1.28 line covers k8s 1.32/1.33/1.34).
  Note: the upstream chart does **not** publish a chart for operator `1.28.3` — the 1.28 line
  tops out at `1.28.1` (chart `0.27.1`), and chart `0.28.x` jumps to operator `1.29.x`, which
  does **not** cover k8s 1.32. So `1.28.1` is the target patch. See issue #5.

## Troubleshooting

### Operator not starting

Check logs:
```bash
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg
```

### CRDs not created

Ensure Helm dependencies are updated:
```bash
helm dependency update
```

### Webhook issues

Check webhook configuration:
```bash
kubectl get validatingwebhookconfigurations | grep cnpg
kubectl get mutatingwebhookconfigurations | grep cnpg
```

## Notes

- The operator creates its own namespace: `cnpg-system`
- This is cluster-wide infrastructure
- Deploy before deploying any PostgreSQL clusters
- All PostgreSQL environments will use this same operator
- The operator version is managed through the Chart.yaml dependency

## References

- [CloudNativePG Documentation](https://cloudnative-pg.io/)
- [CloudNativePG Helm Charts](https://github.com/cloudnative-pg/charts)
- [Operator Configuration](https://cloudnative-pg.io/documentation/current/operator_conf/)
