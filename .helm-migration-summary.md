# Helm Migration Summary

**Date:** 2026-02-05  
**Status:** ✅ COMPLETED

## Migration Overview

Successfully migrated CloudNativePG deployment from Kustomize to official Helm charts.

## What Was Done

### ✅ Phase 1: Archive Kustomize Configurations
- Moved all Kustomize files to `kustomize-deprecated/` folders
- Preserved in: `apps/platform/cnpg-operator/kustomize-deprecated/`
- Preserved in: `apps/data/cnpg/kustomize-deprecated/`
- Preserved in: `clusters/local/kustomize-deprecated/`
- Preserved in: `clusters/cloud/kustomize-deprecated/`

### ✅ Phase 2: CNPG Operator Helm Chart
Created in `apps/platform/cnpg-operator/`:
- `Chart.yaml` - Uses official `cnpg/cloudnative-pg` chart as dependency
- `values.yaml` - Operator configuration (cluster-wide, resources, monitoring)
- `README.md` - Comprehensive deployment documentation

### ✅ Phase 3: CNPG Cluster Helm Chart
Created in `apps/data/cnpg/`:
- `Chart.yaml` - Uses official `cnpg/cluster` chart as dependency
- `values.yaml` - Base cluster configuration (shared across all environments)
- `README.md` - Cluster deployment documentation

Created environment-specific values in `clusters/`:
- `clusters/local/dev/values.yaml` - Local dev (1 instance, 250m CPU, 512Mi RAM, 20Gi)
- `clusters/local/qa/values.yaml` - Local QA (2 instances, 500m CPU, 1Gi RAM, 30Gi)
- `clusters/local/prod/values.yaml` - Local prod (3 instances, 1 CPU, 2Gi RAM, 50Gi)
- `clusters/cloud/dev/values.yaml` - Cloud dev (2 instances, 500m CPU, 1Gi RAM, 50Gi)
- `clusters/cloud/qa/values.yaml` - Cloud QA (2 instances, 1 CPU, 2Gi RAM, 75Gi)
- `clusters/cloud/prod/values.yaml` - Cloud prod (3 instances, 2 CPU, 4Gi RAM, 200Gi)

### ✅ Phase 4: Reorganized Clusters Directory
Created new structure:
```
clusters/
├── local/
│   ├── dev/
│   │   ├── secrets/
│   │   │   ├── secret-app.example.yaml
│   │   │   └── .gitignore
│   │   └── README.md
│   ├── qa/
│   └── prod/
└── cloud/
    ├── dev/
    ├── qa/
    └── prod/
```

Each environment has:
- Secrets directory with example and .gitignore
- Environment-specific README with deployment instructions

### ✅ Phase 5: Documentation Updates
- Updated main `README.md` with Helm instructions
- Created `MIGRATION.md` with detailed migration guide
- Created READMEs for:
  - `apps/platform/cnpg-operator/README.md`
  - `apps/data/cnpg/README.md`
  - `clusters/local/README.md`
  - `clusters/cloud/README.md`
  - `clusters/README.md`
  - All 6 environment READMEs

### ✅ Phase 6: Argo CD Applications
Created in `argocd/`:
- `operator/cnpg-operator.yaml` - Operator Application
- `clusters/local/cnpg-cluster-dev.yaml` - Local dev Application
- `clusters/local/cnpg-cluster-qa.yaml` - Local QA Application
- `clusters/local/cnpg-cluster-prod.yaml` - Local prod Application
- `clusters/cloud/cnpg-cluster-dev.yaml` - Cloud dev Application
- `clusters/cloud/cnpg-cluster-qa.yaml` - Cloud QA Application
- `clusters/cloud/cnpg-cluster-prod.yaml` - Cloud prod Application
- `README.md` - Argo CD deployment guide

## Key Changes

### Before (Kustomize)
- Raw manifest URLs for operator
- Custom cluster manifests with JSON patches
- Complex overlay structure
- Manual namespace management

### After (Helm)
- Official CloudNativePG Helm charts
- Clean values files for configuration
- Environment-specific values files
- Automatic namespace management
- Better GitOps integration

## Configuration Mapping

All previous Kustomize configurations have been mapped to Helm values:

| Component | Kustomize | Helm |
|-----------|-----------|------|
| Operator | Raw manifest URL | Official chart dependency |
| Instances | JSON patch | `cluster.instances` |
| Resources | JSON patch | `cluster.resources` |
| Storage | JSON patch | `cluster.storage` |
| Affinity | JSON patch | `cluster.affinity` |
| PostgreSQL params | JSON patch | `cluster.postgresql.parameters` |

## Next Steps

### 1. Update Helm Dependencies
```bash
cd apps/platform/cnpg-operator
helm dependency update

cd ../data/cnpg
helm dependency update
```

### 2. Deploy Operator
```bash
cd apps/platform/cnpg-operator
helm upgrade --install cnpg-operator . \
  --namespace cnpg-system \
  --create-namespace \
  --values values.yaml
```

### 3. Create Secrets
```bash
cd clusters/local/dev
cp secrets/secret-app.example.yaml secrets/secret-app.yaml
# Edit password
kubeseal --format=yaml --namespace data-dev \
  < secrets/secret-app.yaml > secrets/sealedsecret-app.yaml
kubectl apply -f secrets/sealedsecret-app.yaml
rm secrets/secret-app.yaml
```

### 4. Deploy Cluster
```bash
cd ../../..
helm upgrade --install platform-postgres-dev apps/data/cnpg \
  --namespace data-dev \
  --create-namespace \
  --values apps/data/cnpg/values.yaml \
  --values clusters/local/dev/values.yaml
```

### 5. Or Use Argo CD
```bash
# Update repoURL in manifests first
kubectl apply -f argocd/operator/cnpg-operator.yaml
kubectl apply -f argocd/clusters/local/cnpg-cluster-dev.yaml
```

## Benefits

✅ **Official Support** - Using CloudNativePG's official charts  
✅ **Simplified Updates** - Easy chart version management  
✅ **Better Parameterization** - Clean values vs complex patches  
✅ **Ecosystem Integration** - Better Helm tooling support  
✅ **Cleaner GitOps** - Improved Argo CD integration  
✅ **Easier Maintenance** - Less custom manifest management  

## Rollback

If needed, Kustomize files are preserved in `kustomize-deprecated/` folders.

See `MIGRATION.md` for detailed rollback procedures.

## Files Created

### Helm Charts
- `apps/platform/cnpg-operator/Chart.yaml`
- `apps/platform/cnpg-operator/values.yaml`
- `apps/data/cnpg/Chart.yaml`
- `apps/data/cnpg/values.yaml`
- `clusters/local/dev/values.yaml`
- `clusters/local/qa/values.yaml`
- `clusters/local/prod/values.yaml`
- `clusters/cloud/dev/values.yaml`
- `clusters/cloud/qa/values.yaml`
- `clusters/cloud/prod/values.yaml`

### Documentation
- `README.md` (updated)
- `MIGRATION.md` (new)
- `apps/platform/cnpg-operator/README.md`
- `apps/data/cnpg/README.md`
- `clusters/README.md`
- `clusters/local/README.md`
- `clusters/cloud/README.md`
- 6 environment-specific READMEs
- `argocd/README.md`

### Argo CD Applications
- 7 Application manifests for GitOps deployment

### Secrets Structure
- 6 environment secret directories with examples and .gitignore

## Total Files

- **Created:** 40+ new files
- **Moved:** 20+ files to kustomize-deprecated
- **Updated:** Main README.md

## Validation Checklist

Before deploying to production:

- [ ] Update Helm dependencies
- [ ] Test operator deployment in dev
- [ ] Create secrets for all environments
- [ ] Test cluster deployment in dev
- [ ] Verify database connectivity
- [ ] Test QA environment
- [ ] Update Argo CD Applications with correct repoURL
- [ ] Deploy to production during maintenance window
- [ ] Verify all services are healthy
- [ ] Document any issues or adjustments

## Support

- Main documentation: `README.md`
- Migration guide: `MIGRATION.md`
- Component READMEs in each directory
- Official docs: https://cloudnative-pg.io/
- Helm charts: https://github.com/cloudnative-pg/charts
