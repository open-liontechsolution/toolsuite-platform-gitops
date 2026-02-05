# Argo CD Applications for CloudNativePG

This directory contains Argo CD Application manifests for deploying CloudNativePG PostgreSQL clusters.

## Structure

```
argocd/
└── clusters/
    ├── local/
    │   ├── dev.yaml      # Local development cluster
    │   ├── qa.yaml       # Local QA cluster
    │   └── prod.yaml     # Local production cluster
    └── cloud/
        ├── dev.yaml      # Cloud development cluster
        ├── qa.yaml       # Cloud QA cluster
        └── prod.yaml     # Cloud production cluster
```

## Deployment

### Prerequisites

1. **CNPG Operator** must be deployed first:
   ```bash
   kubectl apply -f apps/platform/cnpg-operator/argocd/operator.yaml
   ```

2. **Sealed Secrets Controller** must be installed
3. **Secrets encrypted** and added to environment values files

### Deploy a Cluster

```bash
# Local development
kubectl apply -f apps/data/cnpg/argocd/clusters/local/dev.yaml

# Local QA
kubectl apply -f apps/data/cnpg/argocd/clusters/local/qa.yaml

# Local production
kubectl apply -f apps/data/cnpg/argocd/clusters/local/prod.yaml

# Cloud environments
kubectl apply -f apps/data/cnpg/argocd/clusters/cloud/dev.yaml
kubectl apply -f apps/data/cnpg/argocd/clusters/cloud/qa.yaml
kubectl apply -f apps/data/cnpg/argocd/clusters/cloud/prod.yaml
```

### Verify Deployment

```bash
# Check Application
kubectl get application -n argocd cnpg-cluster-local-dev

# Check cluster status
kubectl get cluster -n data-dev
kubectl cnpg status platform-postgres -n data-dev

# Check pods
kubectl get pods -n data-dev
```

## Application Configuration

Each Application manifest includes:

- **Source**: Points to `apps/data/cnpg` chart
- **Values Files**: Base + environment-specific values
- **Destination**: Target namespace (data-dev, data-qa, data-prod)
- **Sync Policy**: Automated for dev/qa, manual for prod

### Example Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cnpg-cluster-local-dev
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/toolsuite-platform-gitops
    path: apps/data/cnpg
    targetRevision: main
    helm:
      releaseName: platform-postgres-dev
      valueFiles:
        - values.yaml
        - environments/local/dev.yaml  # ← Simple path, no ../
  destination:
    server: https://kubernetes.default.svc
    namespace: data-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Sync Policies

### Development & QA (Automated)

```yaml
syncPolicy:
  automated:
    prune: true        # Remove resources not in Git
    selfHeal: true     # Auto-sync on drift
    allowEmpty: false
```

### Production (Manual)

```yaml
syncPolicy:
  # No automated section - requires manual sync
  syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
```

To sync production manually:

```bash
# Via kubectl
kubectl patch application cnpg-cluster-local-prod -n argocd \
  --type merge -p '{"operation":{"sync":{}}}'

# Via Argo CD CLI
argocd app sync cnpg-cluster-local-prod

# Via UI - click "Sync" button
```

## Creating from Argo CD UI

If you prefer to create Applications from the UI:

1. **General**
   - Application Name: `cnpg-cluster-local-dev`
   - Project: `default`

2. **Source**
   - Repository URL: `https://github.com/your-org/toolsuite-platform-gitops`
   - Revision: `main`
   - Path: `apps/data/cnpg`

3. **Helm**
   - Values Files:
     - `values.yaml`
     - `environments/local/dev.yaml`
   - Release Name: `platform-postgres-dev`

4. **Destination**
   - Cluster URL: `https://kubernetes.default.svc`
   - Namespace: `data-dev`

5. **Sync Options**
   - ✅ Auto-Create Namespace
   - ✅ Server-Side Apply
   - ✅ Automated Sync (for dev/qa)

## Troubleshooting

### Application OutOfSync

```bash
# View diff
argocd app diff cnpg-cluster-local-dev

# Force sync
argocd app sync cnpg-cluster-local-dev --force
```

### Cluster Not Starting

```bash
# Check operator is running
kubectl get pods -n cnpg-system

# Check Application status
kubectl describe application cnpg-cluster-local-dev -n argocd

# Check cluster events
kubectl describe cluster platform-postgres -n data-dev
```

### Secret Not Found

Ensure the SealedSecret was created and unsealed:

```bash
# Check SealedSecret
kubectl get sealedsecret -n data-dev

# Check unsealed Secret
kubectl get secret platform-postgres-app -n data-dev
```

## References

- [Chart README](../README.md)
- [Environment Values](../environments/README.md)
- [Sealed Secrets Guide](../../../docs/SEALED-SECRETS-GUIDE.md)
- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
