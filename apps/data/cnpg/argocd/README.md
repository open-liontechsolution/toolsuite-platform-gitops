# Argo CD Applications for CloudNativePG

This directory contains Argo CD Application manifests for deploying CloudNativePG PostgreSQL clusters.

## Structure

```
argocd/
└── clusters/
    └── local/
        └── dev.yaml      # cnpg-cluster-local-dev -> release platform-postgres-dev, ns data-dev
```

Las Applications de `qa`, `prod` y `cloud/*` se borraron en la issue #44: ninguna existía en el clúster y sus
values de entorno no configuraban nada (ver `../environments/README.md`).

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
kubectl apply -f apps/data/cnpg/argocd/clusters/local/dev.yaml
argocd app sync cnpg-cluster-local-dev
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
- **Destination**: namespace `data-dev`
- **Sync Policy**: automated (prune + selfHeal)
- **ignoreDifferences**: `/status` del `Cluster`, para que el estado que escribe el operator no genere diff

El `metadata.name` de la Application (`cnpg-cluster-local-dev`) **no** coincide con el `releaseName`
(`platform-postgres-dev`), y eso es intencionado: el `releaseName` es load-bearing, tiene que seguir siendo el
del release vivo o los recursos se recrean con otros nombres y los viejos se podan.

### Example Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cnpg-cluster-local-dev
  namespace: argocd
spec:
  project: tools
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

## Sync Policy

```yaml
syncPolicy:
  automated:
    prune: true        # Remove resources not in Git
    selfHeal: true     # Auto-sync on drift
    allowEmpty: false
  syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
```

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
kubectl get secret cnpg-backup-s3-creds -n data-dev   # credencial del backup a MinIO
```

### Backup failing / ContinuousArchiving en False

```bash
kubectl -n data-dev get backup -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,ERROR:.status.error'
kubectl -n data-dev get cluster platform-postgres-dev \
  -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")]}'
```

Lo primero que hay que descartar es que el Secret `cnpg-backup-s3-creds` no se haya desellado.

## References

- [Chart README](../README.md)
- [Environment Values](../environments/README.md)
- [Sealed Secrets Guide](../../../docs/SEALED-SECRETS-GUIDE.md)
- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
