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
    repoURL: https://github.com/<your-org>/toolsuite-platform-gitops
    path: apps/platform/cnpg-operator
    targetRevision: main
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: cnpg-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

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

## Migration from Kustomize

If you were previously using Kustomize, the old configuration is preserved in `kustomize-deprecated/` for reference. The Helm chart provides the same functionality with better parameterization.

See the main repository's `MIGRATION.md` for detailed migration instructions.

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
