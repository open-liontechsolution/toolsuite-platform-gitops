# Local Cluster Overlays

This directory contains Kustomize overlays for **local k3s deployments** using Longhorn as the storage provider.

## Available Environments

### Development (`dev/`)
- **Instances:** 1 PostgreSQL instance
- **Resources:** 250m CPU, 512Mi RAM (limits: 1 CPU, 2Gi RAM)
- **Storage:** 20Gi backup volume
- **Use case:** Local development, testing, proof of concept

### QA (`qa/`)
- **Instances:** 2 PostgreSQL instances (HA)
- **Resources:** 500m CPU, 1Gi RAM (limits: 2 CPU, 3Gi RAM)
- **Storage:** 30Gi backup volume
- **Use case:** Integration testing, QA validation

### Production (`prod/`)
- **Instances:** 3 PostgreSQL instances (full HA)
- **Resources:** 1 CPU, 2Gi RAM (limits: 4 CPU, 8Gi RAM)
- **Storage:** 50Gi backup volume
- **Use case:** Production-grade local deployment

## Prerequisites

- k3s cluster running
- Longhorn installed and configured
- kubectl configured to access the cluster
- (Optional) Argo CD for GitOps deployment

## Deployment

### Using kubectl + kustomize

```bash
# Deploy development environment
kustomize build clusters/local/dev | kubectl apply -f -

# Deploy QA environment
kustomize build clusters/local/qa | kubectl apply -f -

# Deploy production environment
kustomize build clusters/local/prod | kubectl apply -f -
```

### Using Argo CD

Create an Application pointing to the desired environment:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: data-cnpg-local-dev
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<your-org>/toolsuite-platform-gitops
    path: clusters/local/dev
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: data-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

## Storage Configuration

All environments use **Longhorn** as the storage class:
- Database volumes: `storageClass: longhorn`
- Backup volumes: `storageClass: longhorn`

Ensure Longhorn is properly configured with sufficient disk space on your nodes.

## Verification

After deployment:

```bash
# Check CNPG operator
kubectl get pods -n cnpg-system

# Check PostgreSQL cluster
kubectl get cluster -n data-system
kubectl get pods -n data-system

# Check services
kubectl get svc -n data-system

# Check backups
kubectl get cronjob -n data-system
kubectl get pvc -n data-system
```

## Customization

To customize an environment, edit the corresponding `kustomization.yaml` file and adjust:
- Instance count
- Resource requests/limits
- Storage sizes
- Backup schedules

## Notes

- All environments include automated logical backups via CronJob
- Longhorn provides additional snapshot capabilities for disaster recovery
- Consider using both backup strategies for production environments
