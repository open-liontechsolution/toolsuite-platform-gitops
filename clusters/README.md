# Cluster Deployments

This directory contains environment-specific configurations for deploying CloudNativePG PostgreSQL clusters using Helm charts.

## Structure

```
clusters/
├── local/                          # Local k3s deployments
│   ├── dev/                        # Development environment
│   │   ├── secrets/                # Sealed secrets
│   │   └── README.md
│   ├── qa/                         # QA environment
│   ├── prod/                       # Production environment
│   ├── README.md
│   └── kustomize-deprecated/       # Old Kustomize configs (archived)
├── cloud/                          # Cloud deployments (EKS/GKE/AKS)
│   ├── dev/                        # Development environment
│   │   ├── secrets/                # Sealed secrets
│   │   └── README.md
│   ├── qa/                         # QA environment
│   ├── prod/                       # Production environment
│   ├── README.md
│   └── kustomize-deprecated/       # Old Kustomize configs (archived)
└── README.md                       # This file
```

## Overview

Each environment directory contains:
- **secrets/** - Sealed secrets for the environment (gitignored plain secrets)
- **README.md** - Environment-specific deployment instructions

The actual Helm chart configurations are in `apps/data/cnpg/` with environment-specific values files:
- `values-local-dev.yaml`, `values-local-qa.yaml`, `values-local-prod.yaml`
- `values-cloud-dev.yaml`, `values-cloud-qa.yaml`, `values-cloud-prod.yaml`

## Deployment Methods

### Method 1: Helm CLI

```bash
# 1. Create and apply secret
cd clusters/local/dev
cp secrets/secret-app.example.yaml secrets/secret-app.yaml
# Edit and set password
kubeseal --format=yaml --namespace data-dev \
  < secrets/secret-app.yaml > secrets/sealedsecret-app.yaml
kubectl apply -f secrets/sealedsecret-app.yaml
rm secrets/secret-app.yaml

# 2. Deploy cluster
cd ../../..  # Return to repo root
helm dependency update apps/data/cnpg
helm upgrade --install platform-postgres-dev apps/data/cnpg \
  --namespace data-dev \
  --create-namespace \
  --values apps/data/cnpg/values.yaml \
  --values clusters/local/dev/values.yaml
```

### Method 2: Argo CD (Recommended)

```bash
# Apply Argo CD Application manifest
kubectl apply -f argocd/clusters/local/cnpg-cluster-dev.yaml

# Check sync status
kubectl get application -n argocd cnpg-cluster-local-dev
```

See `argocd/README.md` for detailed GitOps deployment instructions.

## Environment Comparison

### Local Environments (k3s + Longhorn)

| Environment | Namespace | Instances | CPU/Memory | Storage | Values File |
|-------------|-----------|-----------|------------|---------|-------------|
| dev         | data-dev  | 1         | 250m/512Mi | 20Gi    | clusters/local/dev/values.yaml |
| qa          | data-qa   | 2         | 500m/1Gi   | 30Gi    | clusters/local/qa/values.yaml |
| prod        | data-prod | 3         | 1/2Gi      | 50Gi    | clusters/local/prod/values.yaml |

**Storage Class:** `longhorn`

### Cloud Environments (EKS/GKE/AKS)

| Environment | Namespace | Instances | CPU/Memory | Storage | Values File |
|-------------|-----------|-----------|------------|---------|-------------|
| dev         | data-dev  | 2         | 500m/1Gi   | 50Gi    | clusters/cloud/dev/values.yaml |
| qa          | data-qa   | 2         | 1/2Gi      | 75Gi    | clusters/cloud/qa/values.yaml |
| prod        | data-prod | 3         | 2/4Gi      | 200Gi   | clusters/cloud/prod/values.yaml |

**Storage Class:** `gp3` (AWS), `pd-ssd` (GCP), `managed-premium` (Azure)

## Secrets Management

Each environment requires a secret named `platform-postgres-app` in its namespace.

### Creating Secrets

1. **Copy example:**
   ```bash
   cp clusters/local/dev/secrets/secret-app.example.yaml \
      clusters/local/dev/secrets/secret-app.yaml
   ```

2. **Edit password:**
   ```yaml
   stringData:
     username: platform
     password: "your-strong-password-here"
   ```

3. **Seal with kubeseal:**
   ```bash
   kubeseal --format=yaml --namespace data-dev \
     < clusters/local/dev/secrets/secret-app.yaml \
     > clusters/local/dev/secrets/sealedsecret-app.yaml
   ```

4. **Apply:**
   ```bash
   kubectl apply -f clusters/local/dev/secrets/sealedsecret-app.yaml
   ```

5. **Clean up:**
   ```bash
   rm clusters/local/dev/secrets/secret-app.yaml
   ```

**Important:** Never commit plain secrets to Git. The `.gitignore` files in `secrets/` directories prevent this.

## Verification

After deployment, verify the cluster:

```bash
# Check Helm release
helm list -n data-dev

# Check cluster status
kubectl get cluster -n data-dev
kubectl cnpg status platform-postgres -n data-dev

# Check pods
kubectl get pods -n data-dev

# Check services
kubectl get svc -n data-dev

# Expected services:
# - platform-postgres-rw (read-write primary)
# - platform-postgres-ro (read-only replicas)
# - platform-postgres-r  (read service)
```

## Connecting to PostgreSQL

### Port-forward

```bash
kubectl port-forward -n data-dev svc/platform-postgres-rw 5432:5432
```

Then connect:
```bash
psql -h localhost -U platform -d platform
```

### Get Password

```bash
kubectl get secret platform-postgres-app -n data-dev \
  -o jsonpath='{.data.password}' | base64 -d
```

## Migration from Kustomize

Previous Kustomize configurations are preserved in `kustomize-deprecated/` folders. The new Helm-based approach provides:

- Official CloudNativePG chart support
- Cleaner parameterization with values files
- Easier multi-environment management
- Better GitOps integration

See `MIGRATION.md` in the repository root for detailed migration instructions.

## Troubleshooting

### Secret Not Found

```bash
# Check if secret exists
kubectl get secret platform-postgres-app -n data-dev

# If missing, create and apply sealed secret
```

### Cluster Not Starting

```bash
# Check operator is running
kubectl get pods -n cnpg-system

# Check cluster events
kubectl describe cluster platform-postgres -n data-dev

# Check operator logs
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg
```

### Storage Issues

```bash
# Check storage class exists
kubectl get storageclass

# For local: check Longhorn
kubectl get pods -n longhorn-system

# Check PVC status
kubectl get pvc -n data-dev
```

## References

- [Local Deployments README](local/README.md)
- [Cloud Deployments README](cloud/README.md)
- [Argo CD Applications](../argocd/README.md)
- [Migration Guide](../MIGRATION.md)
- [CloudNativePG Documentation](https://cloudnative-pg.io/)
