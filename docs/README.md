# Documentation Index

Welcome to the toolsuite-platform-gitops documentation. This directory contains all guides, migration history, and reference documentation for the platform.

## 📚 Getting Started

- **[Main README](../README.md)** - Project overview and quick start
- **[Migration Guide](MIGRATION.md)** - Kustomize to Helm migration details
- **[Deployment Guide](guides/deployment.md)** - Step-by-step deployment instructions
- **[Troubleshooting Guide](guides/troubleshooting.md)** - Common issues and solutions

## 🔐 Configuration

- **[Sealed Secrets Guide](SEALED-SECRETS-GUIDE.md)** - Managing secrets with SealedSecrets
- **[Environment Configuration](../apps/data/cnpg/environments/README.md)** - Environment-specific values
- **[Argo CD Applications](../apps/data/cnpg/argocd/README.md)** - Argo CD Application manifests

## 📖 Component Documentation

### CloudNativePG
- **[CNPG Cluster Chart](../apps/data/cnpg/README.md)** - PostgreSQL cluster Helm chart
- **[CNPG Operator Chart](../apps/platform/cnpg-operator/README.md)** - Operator Helm chart

### Clusters
- **[Clusters Overview](../clusters/README.md)** - Reference documentation for environments

## 📜 Migration History

Historical documentation of major changes to the repository structure:

- **[Helm Migration](migration/helm-migration.md)** - Initial migration from Kustomize to Helm
- **[Values Reorganization](migration/values-reorganization.md)** - Moving values to cluster directories
- **[SealedSecret Implementation](migration/sealedsecret-implementation.md)** - Integrating secrets into Helm
- **[Structure Reorganization](migration/structure-reorganization.md)** - Consolidating into chart directories

## 🎯 Quick Links

### Deployment
```bash
# Deploy operator
kubectl apply -f apps/platform/cnpg-operator/argocd/operator.yaml

# Deploy cluster
kubectl apply -f apps/data/cnpg/argocd/clusters/local/dev.yaml
```

### Configuration Locations
- **Operator config**: `apps/platform/cnpg-operator/values.yaml`
- **Base cluster config**: `apps/data/cnpg/values.yaml`
- **Environment configs**: `apps/data/cnpg/environments/{local|cloud}/{env}.yaml`
- **Argo CD manifests**: `apps/data/cnpg/argocd/clusters/{local|cloud}/{env}.yaml`

## 🔍 Finding What You Need

### I want to...

**Deploy a new environment**
→ See [Deployment Guide](guides/deployment.md)

**Configure secrets**
→ See [Sealed Secrets Guide](SEALED-SECRETS-GUIDE.md)

**Understand the migration**
→ See [Migration Guide](MIGRATION.md)

**Troubleshoot an issue**
→ See [Troubleshooting Guide](guides/troubleshooting.md)

**Modify cluster configuration**
→ See [Environment Configuration](../apps/data/cnpg/environments/README.md)

**Create Argo CD Application**
→ See [Argo CD Applications](../apps/data/cnpg/argocd/README.md)

## 📝 Contributing

When updating documentation:

1. Keep the main README concise and focused on quick start
2. Place detailed guides in `docs/guides/`
3. Document major changes in `docs/migration/`
4. Update this index when adding new documentation

## 🏗️ Repository Structure

```
toolsuite-platform-gitops/
├── README.md                    # Main project README
├── apps/
│   ├── platform/               # Platform components
│   │   └── cnpg-operator/      # CNPG operator Helm chart
│   └── data/                   # Data layer
│       └── cnpg/               # PostgreSQL cluster Helm chart
├── clusters/                   # Reference documentation
│   ├── local/                  # Local k3s environments
│   └── cloud/                  # Cloud environments
└── docs/                       # ← You are here
    ├── README.md               # This file
    ├── MIGRATION.md            # Migration guide
    ├── SEALED-SECRETS-GUIDE.md # Secrets management
    ├── migration/              # Historical changes
    └── guides/                 # How-to guides
```

## 📞 Support

For questions or issues:
1. Check the [Troubleshooting Guide](guides/troubleshooting.md)
2. Review relevant component documentation
3. Check migration history for context on changes

---

**Last Updated:** February 2026  
**Repository:** https://github.com/open-liontechsolution/toolsuite-platform-gitops
