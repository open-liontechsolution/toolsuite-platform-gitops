# Local Cluster Deployments

PostgreSQL cluster deployments for **local k3s clusters** using Longhorn storage.

## Overview

This directory contains Helm-based configurations for deploying CloudNativePG PostgreSQL clusters to local k3s environments. Each environment is optimized for different use cases.

## Available Environments

| Environment | Namespace | Instances | CPU/Memory | Storage | Use Case |
|-------------|-----------|-----------|------------|---------|----------|
| **dev**     | data-dev  | 1         | 250m/512Mi | 20Gi    | Development, testing |
| **qa**      | data-qa   | 2         | 500m/1Gi   | 30Gi    | Integration testing |
| **prod**    | data-prod | 3         | 1/2Gi      | 50Gi    | Production-grade local |

## Prerequisites

- k3s cluster running
- Longhorn installed and configured as storage class
- CloudNativePG operator deployed (see `apps/platform/cnpg-operator/`)
- kubectl and Helm 3.x installed

## Quick Start

1. **Deploy the operator** (once per cluster):
```bash
cd apps/platform/cnpg-operator
helm dependency update
helm upgrade --install cnpg-operator . \
  --namespace cnpg-system \
  --create-namespace
```

2. **Create application secret** for your environment:
```bash
cd clusters/local/dev  # or qa/prod
cp secrets/secret-app.example.yaml secrets/secret-app.yaml
# Edit and set password
kubeseal --format=yaml --namespace data-dev \
  < secrets/secret-app.yaml > secrets/sealedsecret-app.yaml
kubectl apply -f secrets/sealedsecret-app.yaml
rm secrets/secret-app.yaml
```

3. **Deploy PostgreSQL cluster**:
```bash
cd ../../..  # Return to repo root
helm dependency update apps/data/cnpg
helm upgrade --install platform-postgres-dev apps/data/cnpg \
  --namespace data-dev \
  --create-namespace \
  --values apps/data/cnpg/values.yaml \
  --values ../../clusters/local/dev/values.yaml
```

## Storage Configuration

All local environments use **Longhorn** as the storage class:
- Provides replicated block storage across nodes
- Supports snapshots and backups
- Suitable for local production workloads

Ensure Longhorn is properly configured with sufficient disk space.

## Verification

```bash
# Check operator
kubectl get pods -n cnpg-system

# Check cluster (replace data-dev with your namespace)
kubectl get cluster -n data-dev
kubectl cnpg status platform-postgres -n data-dev
kubectl get pods -n data-dev
kubectl get svc -n data-dev
```

## Environment Details

### Development (dev/)
- Single instance for minimal resource usage
- Node affinity prefers `node.kubernetes.io/performance=high`
- Suitable for local development and testing
- See `dev/README.md` for details

### QA (qa/)
- Two instances for high availability testing
- Node affinity prefers `workload=db`
- Suitable for integration testing
- See `qa/README.md` for details

### Production (prod/)
- Three instances for full high availability
- Node affinity prefers `workload=db`
- Production-grade configuration
- See `prod/README.md` for details

## Migration from Kustomize

Previous Kustomize configurations are preserved in `kustomize-deprecated/` for reference. The new Helm-based approach provides:
- Cleaner parameterization with values files
- Official CloudNativePG chart support
- Easier upgrades and maintenance

See the main repository's `MIGRATION.md` for migration instructions.

## Troubleshooting

### Longhorn Issues
```bash
kubectl get pods -n longhorn-system
kubectl get storageclass
```

### Cluster Not Starting
```bash
kubectl describe cluster platform-postgres -n data-dev
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg
```

### Connection Issues
```bash
kubectl get svc -n data-dev
kubectl port-forward -n data-dev svc/platform-postgres-rw 5432:5432
```

## References

- [CloudNativePG Documentation](https://cloudnative-pg.io/)
- [Longhorn Documentation](https://longhorn.io/docs/)
- [k3s Documentation](https://docs.k3s.io/)
