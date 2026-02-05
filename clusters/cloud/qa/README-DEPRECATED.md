# Local Development Environment - DEPRECATED

⚠️ **This directory structure is deprecated.**

## New Location

All configuration has been moved to the CNPG Helm chart directory:

- **Values file**: `apps/data/cnpg/environments/local/dev.yaml`
- **Argo CD Application**: `apps/data/cnpg/argocd/clusters/local/dev.yaml`
- **Documentation**: `apps/data/cnpg/README.md`

## Quick Start (New Approach)

### 1. Encrypt Secrets

```bash
# Encrypt username
echo -n "platform" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace data-dev \
  --name platform-postgres-app

# Encrypt password
echo -n "your-password" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace data-dev \
  --name platform-postgres-app
```

### 2. Update Values File

Edit `apps/data/cnpg/environments/local/dev.yaml` with encrypted values.

### 3. Deploy

```bash
# Via kubectl
kubectl apply -f apps/data/cnpg/argocd/clusters/local/dev.yaml

# Or via Helm
cd apps/data/cnpg
helm upgrade --install platform-postgres-dev . \
  --namespace data-dev \
  --create-namespace \
  --values values.yaml \
  --values environments/local/dev.yaml
```

## Why the Change?

✅ **Simpler paths** - No more `../` navigation  
✅ **UI-friendly** - Works in Argo CD UI  
✅ **Self-contained** - Everything in the chart directory  
✅ **Easier to find** - All configs in one place  

## References

- [CNPG Chart README](../../../apps/data/cnpg/README.md)
- [Environment Values](../../../apps/data/cnpg/environments/README.md)
- [Argo CD Applications](../../../apps/data/cnpg/argocd/README.md)
- [Sealed Secrets Guide](../../../docs/SEALED-SECRETS-GUIDE.md)
