# Migration Guide: Kustomize to Helm Charts

This document describes the migration from Kustomize-based deployments to Helm charts using the official CloudNativePG charts.

## Overview

The repository has been restructured to use Helm charts instead of Kustomize for deploying CloudNativePG components. This migration provides:

- **Official support**: Using CloudNativePG's official Helm charts
- **Simplified updates**: Easier chart version management
- **Better parameterization**: Cleaner values files vs Kustomize patches
- **Ecosystem integration**: Better compatibility with Helm-based tools

## What Changed

### Before (Kustomize)

```text
apps/
├─ platform/cnpg-operator/
│  ├─ kustomization.yaml          # Referenced raw manifest URL
│  └─ README.md
└─ data/cnpg/
   ├─ cluster.yaml                # Custom cluster manifest
   ├─ backup-cronjob.yaml         # Custom backup job
   ├─ backup-pvc.yaml             # Backup storage
   ├─ kustomization.yaml
   └─ README.md

clusters/local/dev/
├─ kustomization.yaml             # Patches for customization
└─ README.md
```

### After (Helm)

```text
apps/
├─ platform/cnpg-operator/
│  ├─ Chart.yaml                  # Helm chart with official operator dependency
│  ├─ values.yaml                 # Operator configuration
│  ├─ README.md
│  └─ kustomize-deprecated/       # Old files preserved
└─ data/cnpg/
   ├─ Chart.yaml                  # Helm chart with official cluster dependency
   ├─ values.yaml                 # Base configuration
   ├─ values-local-dev.yaml       # Environment-specific overrides
   ├─ values-local-qa.yaml
   ├─ values-local-prod.yaml
   ├─ values-cloud-dev.yaml
   ├─ values-cloud-qa.yaml
   ├─ values-cloud-prod.yaml
   ├─ README.md
   └─ kustomize-deprecated/       # Old files preserved

clusters/local/dev/
├─ secrets/
│  ├─ secret-app.example.yaml    # Secret template
│  └─ .gitignore
└─ README.md                      # Helm deployment instructions
```

## Migration Steps

### Step 1: Backup Current Deployment

Before migrating, document your current setup:

```bash
# Export current cluster configuration
kubectl get cluster platform-postgres -n data-dev -o yaml > backup-cluster.yaml

# Export current secrets
kubectl get secret platform-postgres-app -n data-dev -o yaml > backup-secret.yaml

# List all resources
kubectl get all -n data-dev > backup-resources.txt
```

### Step 2: Verify Prerequisites

Ensure you have the required tools:

```bash
# Check Helm version (3.x required)
helm version

# Check kubectl access
kubectl cluster-info

# Check kubeseal (for sealed secrets)
kubeseal --version
```

### Step 3: Deploy Operator via Helm

If you already have the operator running via Kustomize, you can migrate it:

```bash
# First, check current operator version
kubectl get deployment -n cnpg-system -o yaml | grep image:

# Update Helm dependencies
cd apps/platform/cnpg-operator
helm dependency update

# Deploy operator (will upgrade existing deployment)
helm upgrade --install cnpg-operator . \
  --namespace cnpg-system \
  --values values.yaml

# Verify operator is still running
kubectl get pods -n cnpg-system
```

**Note:** The Helm chart will manage the existing operator deployment. No downtime is expected.

### Step 4: Migrate Secrets

Secrets need to be recreated in the new structure:

```bash
# For each environment
cd clusters/local/dev

# Copy the example
cp secrets/secret-app.example.yaml secrets/secret-app.yaml

# Edit with your current password (get it from the backup)
# Extract password from backup:
# kubectl get secret platform-postgres-app -n data-dev -o jsonpath='{.data.password}' | base64 -d

# Encrypt with kubeseal
kubeseal --format=yaml --namespace data-dev \
  < secrets/secret-app.yaml \
  > secrets/sealedsecret-app.yaml

# The secret is already in the cluster, so this is just for GitOps
# You don't need to apply it unless you're recreating the namespace

# Clean up
rm secrets/secret-app.yaml
```

### Step 5: Migrate Cluster Configuration

Map your Kustomize patches to Helm values:

#### Kustomize Patch Example (Old)

```yaml
# clusters/local/dev/kustomization.yaml
patches:
  - target:
      kind: Cluster
      name: platform-postgres
    patch: |-
      - op: replace
        path: /spec/instances
        value: 1
      - op: add
        path: /spec/resources
        value:
          requests:
            cpu: "250m"
            memory: "512Mi"
```

#### Helm Values Example (New)

```yaml
# apps/data/cnpg/values-local-dev.yaml
cluster:
  instances: 1
  resources:
    requests:
      cpu: "250m"
      memory: "512Mi"
```

### Step 6: Deploy Cluster via Helm

You have two options for migration:

#### Option A: In-Place Upgrade (Recommended)

This upgrades the existing cluster without recreating it:

```bash
cd apps/data/cnpg
helm dependency update

# Deploy with Helm (will adopt existing resources)
helm upgrade --install platform-postgres-dev . \
  --namespace data-dev \
  --values values.yaml \
  --values values-local-dev.yaml
```

**Note:** Helm will adopt the existing Cluster resource. No data loss or downtime expected.

#### Option B: Blue-Green Migration

For critical environments, use a blue-green approach:

1. Deploy new cluster with different name
2. Migrate data using pg_dump/pg_restore
3. Switch applications to new cluster
4. Delete old cluster

### Step 7: Verify Migration

After deploying via Helm, verify everything works:

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

# Test connection
kubectl port-forward -n data-dev svc/platform-postgres-rw 5432:5432
# In another terminal:
psql -h localhost -U platform -d platform -c "SELECT version();"
```

### Step 8: Update Argo CD (If Using)

If you're using Argo CD, update your Application manifests:

#### Old Argo CD Application (Kustomize)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: data-cnpg-dev
spec:
  source:
    repoURL: https://github.com/org/repo
    path: clusters/local/dev
    targetRevision: main
  destination:
    namespace: data-dev
```

#### New Argo CD Application (Helm)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cnpg-cluster-local-dev
spec:
  source:
    repoURL: https://github.com/org/repo
    path: apps/data/cnpg
    targetRevision: main
    helm:
      valueFiles:
        - values.yaml
        - values-local-dev.yaml
      releaseName: platform-postgres-dev
  destination:
    namespace: data-dev
```

### Step 9: Clean Up (Optional)

After successful migration, you can remove Kustomize references:

```bash
# The old files are already in kustomize-deprecated/ folders
# You can delete them after confirming everything works:

# Wait at least 1 week to ensure stability
# Then optionally remove deprecated folders:
# rm -rf apps/platform/cnpg-operator/kustomize-deprecated
# rm -rf apps/data/cnpg/kustomize-deprecated
# rm -rf clusters/local/kustomize-deprecated
# rm -rf clusters/cloud/kustomize-deprecated
```

## Configuration Mapping

### Operator Configuration

| Kustomize | Helm Values |
|-----------|-------------|
| Raw manifest URL | `Chart.yaml` dependency |
| N/A | `cloudnative-pg.config.clusterWide: true` |
| N/A | `cloudnative-pg.resources` |
| N/A | `cloudnative-pg.monitoring` |

### Cluster Configuration

| Kustomize Patch | Helm Values Path |
|-----------------|------------------|
| `/spec/instances` | `cluster.instances` |
| `/spec/storage/size` | `cluster.storage.size` |
| `/spec/storage/storageClass` | `cluster.storage.storageClass` |
| `/spec/resources` | `cluster.resources` |
| `/spec/postgresql/parameters` | `cluster.postgresql.parameters` |
| `/spec/affinity` | `cluster.affinity` |
| `/spec/bootstrap` | `cluster.bootstrap` |

### Environment-Specific Values

All environment-specific configurations are now in dedicated values files:

- `values-local-dev.yaml` - Local dev (1 instance, minimal resources)
- `values-local-qa.yaml` - Local QA (2 instances, moderate resources)
- `values-local-prod.yaml` - Local prod (3 instances, production resources)
- `values-cloud-dev.yaml` - Cloud dev (2 instances, cloud storage)
- `values-cloud-qa.yaml` - Cloud QA (2 instances, increased resources)
- `values-cloud-prod.yaml` - Cloud prod (3 instances, full HA)

## Rollback Procedure

If you need to rollback to Kustomize:

### Rollback Operator

```bash
# Uninstall Helm release
helm uninstall cnpg-operator -n cnpg-system

# Redeploy with Kustomize
kustomize build apps/platform/cnpg-operator/kustomize-deprecated | kubectl apply -f -
```

### Rollback Cluster

```bash
# Uninstall Helm release (keeps the Cluster resource)
helm uninstall platform-postgres-dev -n data-dev

# The PostgreSQL cluster will continue running
# Kustomize can manage it again if needed
```

**Note:** The actual PostgreSQL data and cluster are not affected by Helm/Kustomize changes. Only the management method changes.

## Troubleshooting

### Helm Can't Find Dependencies

```bash
cd apps/platform/cnpg-operator  # or apps/data/cnpg
helm dependency update
```

### Cluster Already Exists Error

This is expected during migration. Helm will adopt the existing resource. Use `--force` if needed:

```bash
helm upgrade --install platform-postgres-dev . \
  --namespace data-dev \
  --values values.yaml \
  --values values-local-dev.yaml \
  --force
```

### Values Not Applied

Check that you're specifying all values files:

```bash
helm upgrade --install platform-postgres-dev . \
  --namespace data-dev \
  --values values.yaml \
  --values values-local-dev.yaml \
  --debug --dry-run
```

### Argo CD Sync Issues

If Argo CD shows out-of-sync after migration:

1. Delete the old Application
2. Create the new Helm-based Application
3. Sync the new Application

## Benefits After Migration

### Easier Updates

```bash
# Update operator version
# Edit Chart.yaml dependency version
helm dependency update
helm upgrade cnpg-operator . -n cnpg-system

# Update PostgreSQL version
# Edit values.yaml imageName
helm upgrade platform-postgres-dev . -n data-dev
```

### Cleaner Configuration

- No more complex JSON patches
- Clear hierarchy in values files
- Environment-specific files are self-documenting
- Official chart documentation applies directly

### Better GitOps Integration

- Helm values are easier to template with tools like Helmfile
- Better integration with Argo CD Helm support
- Easier to use with Flux Helm Controller
- Simplified multi-environment management

## Support

If you encounter issues during migration:

1. Check the [CloudNativePG Documentation](https://cloudnative-pg.io/)
2. Review [CloudNativePG Helm Charts](https://github.com/cloudnative-pg/charts)
3. Consult individual component READMEs in this repository
4. Check Kustomize-deprecated folders for reference

## Timeline

Recommended migration timeline:

1. **Week 1:** Migrate dev environment, test thoroughly
2. **Week 2:** Migrate QA environment, validate
3. **Week 3:** Migrate production environment during maintenance window
4. **Week 4+:** Monitor, document lessons learned
5. **After 1 month:** Consider removing kustomize-deprecated folders

## Conclusion

The migration to Helm charts provides a more maintainable and officially supported approach to deploying CloudNativePG. All previous configurations are preserved in `kustomize-deprecated/` folders for reference and rollback if needed.
