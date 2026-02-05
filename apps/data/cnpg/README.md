# CloudNativePG PostgreSQL Cluster (Helm Chart)

This component deploys highly available PostgreSQL clusters using the official CloudNativePG cluster Helm chart. Each environment (dev/qa/prod) can be deployed independently with environment-specific configurations.

## Overview

The cluster chart uses the official [CloudNativePG cluster chart](https://github.com/cloudnative-pg/charts/tree/main/charts/cluster) as a dependency, with customized values for each environment.

## Prerequisites

- CloudNativePG operator must be installed first (see `apps/platform/cnpg-operator/`)
- Kubernetes cluster with appropriate storage class configured
- Helm 3.x installed
- kubectl configured to access the cluster
- Application secret created in target namespace

## Available Environments

### Local Environments (k3s + Longhorn)

| Environment | Namespace | Instances | CPU Request | Memory Request | Storage |
|-------------|-----------|-----------|-------------|----------------|---------|
| **dev**     | data-dev  | 1         | 250m        | 512Mi          | 20Gi    |
| **qa**      | data-qa   | 2         | 500m        | 1Gi            | 30Gi    |
| **prod**    | data-prod | 3         | 1           | 2Gi            | 50Gi    |

### Cloud Environments (EKS/GKE/AKS)

| Environment | Namespace | Instances | CPU Request | Memory Request | Storage |
|-------------|-----------|-----------|-------------|----------------|---------|
| **dev**     | data-dev  | 2         | 500m        | 1Gi            | 50Gi    |
| **qa**      | data-qa   | 2         | 1           | 2Gi            | 75Gi    |
| **prod**    | data-prod | 3         | 2           | 4Gi            | 200Gi   |

## Secrets Management

Before deploying a cluster, create the application secret in the target namespace:

### Option 1: Using Sealed Secrets (Recommended for GitOps)

1. Create a plain secret file:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: platform-postgres-app
  namespace: data-dev  # Change per environment
type: kubernetes.io/basic-auth
stringData:
  username: platform
  password: "your-strong-password-here"
```

2. Encrypt with kubeseal:
```bash
kubeseal --format=yaml \
  --namespace data-dev \
  < secret-app.yaml \
  > sealedsecret-app.yaml
```

3. Apply the sealed secret:
```bash
kubectl apply -f sealedsecret-app.yaml
```

4. Delete the plain secret file:
```bash
rm secret-app.yaml
```

### Option 2: Using kubectl (Development Only)

```bash
kubectl create secret generic platform-postgres-app \
  --namespace data-dev \
  --from-literal=username=platform \
  --from-literal=password=your-password
```

**Security Note:** Never commit plain secrets to Git.

## Deployment

### Using Helm CLI

First, update Helm dependencies:

```bash
cd apps/data/cnpg
helm dependency update
```

Deploy to a specific environment:

```bash
# Local dev environment
helm upgrade --install platform-postgres-dev . \
  --namespace data-dev \
  --create-namespace \
  --values values.yaml \
  --values values-local-dev.yaml

# Local QA environment
helm upgrade --install platform-postgres-qa . \
  --namespace data-qa \
  --create-namespace \
  --values values.yaml \
  --values values-local-qa.yaml

# Local prod environment
helm upgrade --install platform-postgres-prod . \
  --namespace data-prod \
  --create-namespace \
  --values values.yaml \
  --values values-local-prod.yaml

# Cloud environments (use values-cloud-*.yaml)
helm upgrade --install platform-postgres-prod . \
  --namespace data-prod \
  --create-namespace \
  --values values.yaml \
  --values values-cloud-prod.yaml
```

### Using Argo CD

Create an Argo CD Application for each environment:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cnpg-cluster-local-dev
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<your-org>/toolsuite-platform-gitops
    path: apps/data/cnpg
    targetRevision: main
    helm:
      valueFiles:
        - values.yaml
        - values-local-dev.yaml  # Change per environment
      releaseName: platform-postgres-dev
  destination:
    server: https://kubernetes.default.svc
    namespace: data-dev  # Change per environment
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

## Verification

After deployment, verify the cluster is running:

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

# Check PVCs
kubectl get pvc -n data-dev
```

## Connecting to the Database

### From within the cluster

```bash
# Read-write connection (primary)
psql -h platform-postgres-rw.data-dev.svc.cluster.local -U platform -d platform

# Read-only connection (replicas)
psql -h platform-postgres-ro.data-dev.svc.cluster.local -U platform -d platform
```

### Port-forward for local access

```bash
kubectl port-forward -n data-dev svc/platform-postgres-rw 5432:5432

# Then connect locally
psql -h localhost -U platform -d platform
```

### Get credentials

```bash
# Application credentials
kubectl get secret platform-postgres-app -n data-dev -o jsonpath='{.data.password}' | base64 -d

# Superuser credentials (auto-generated by CNPG)
kubectl get secret platform-postgres-superuser -n data-dev -o jsonpath='{.data.password}' | base64 -d
```

## Configuration

### Storage Class

Each environment uses a specific storage class:

- **Local environments:** `longhorn`
- **Cloud environments:** `gp3` (AWS), `pd-ssd` (GCP), `managed-premium` (Azure)

To change the storage class, edit the environment-specific values file:

```yaml
cluster:
  storage:
    storageClass: your-storage-class
```

### Resource Limits

Adjust resources in the environment-specific values file:

```yaml
cluster:
  resources:
    requests:
      cpu: "2"
      memory: "4Gi"
    limits:
      cpu: "8"
      memory: "16Gi"
```

### Instance Count

Change the number of PostgreSQL instances:

```yaml
cluster:
  instances: 3  # 1 for dev, 2 for HA, 3 for full HA
```

### PostgreSQL Parameters

Tune PostgreSQL settings in the values file:

```yaml
cluster:
  postgresql:
    parameters:
      max_connections: "300"
      shared_buffers: "1GB"
      effective_cache_size: "3GB"
```

## Backups

### Logical Backups (Custom CronJob)

The previous Kustomize setup included a custom logical backup CronJob. For Helm deployments, you have two options:

#### Option 1: Use CNPG Native Backups (Recommended)

Configure in the values file:

```yaml
cluster:
  backup:
    enabled: true
    barmanObjectStore:
      destinationPath: s3://your-bucket/backups
      s3Credentials:
        accessKeyId:
          name: backup-credentials
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: backup-credentials
          key: ACCESS_SECRET_KEY
      wal:
        compression: gzip
      data:
        compression: gzip
    retentionPolicy: "30d"
  
  scheduledBackup:
    enabled: true
    name: daily-backup
    schedule: "0 2 * * *"
```

#### Option 2: Custom Backup CronJob

The old backup CronJob and PVC are preserved in `kustomize-deprecated/` and can be deployed separately if needed.

### Restore from Backup

See [CNPG Recovery Documentation](https://cloudnative-pg.io/documentation/current/recovery/) for detailed restore procedures.

## Monitoring

Enable Prometheus monitoring:

```yaml
cluster:
  monitoring:
    enabled: true
    podMonitorEnabled: true
```

Metrics will be available at:
- `http://platform-postgres-rw:9187/metrics` (primary)
- `http://platform-postgres-ro:9187/metrics` (replicas)

## Upgrading

### Upgrade PostgreSQL Version

Update the image in `values.yaml`:

```yaml
cluster:
  imageName: ghcr.io/cloudnative-pg/postgresql:16.5
```

Then upgrade the release:

```bash
helm upgrade platform-postgres-dev . \
  --namespace data-dev \
  --values values.yaml \
  --values values-local-dev.yaml
```

### Upgrade Helm Chart

Update dependencies and upgrade:

```bash
helm dependency update
helm upgrade platform-postgres-dev . --namespace data-dev
```

## Troubleshooting

### Cluster not starting

Check operator logs:
```bash
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg
```

Check cluster events:
```bash
kubectl describe cluster platform-postgres -n data-dev
```

### Connection issues

Verify services exist:
```bash
kubectl get svc -n data-dev | grep platform-postgres
```

Check pod status:
```bash
kubectl get pods -n data-dev
kubectl logs -n data-dev platform-postgres-1
```

### Storage issues

Check PVC status:
```bash
kubectl get pvc -n data-dev
kubectl describe pvc -n data-dev
```

Verify storage class exists:
```bash
kubectl get storageclass
```

## Migration from Kustomize

The previous Kustomize configuration is preserved in `kustomize-deprecated/` for reference. Key differences:

- **Kustomize:** Used patches to customize base manifests
- **Helm:** Uses values files for parameterization
- **Configuration:** All settings are now in values-*.yaml files
- **Deployment:** Helm manages the lifecycle instead of kubectl/kustomize

See the main repository's `MIGRATION.md` for detailed migration instructions.

## References

- [CloudNativePG Documentation](https://cloudnative-pg.io/)
- [CloudNativePG Cluster Chart](https://github.com/cloudnative-pg/charts/tree/main/charts/cluster)
- [PostgreSQL Configuration](https://www.postgresql.org/docs/current/runtime-config.html)
- [CNPG Backup & Recovery](https://cloudnative-pg.io/documentation/current/backup_recovery/)
