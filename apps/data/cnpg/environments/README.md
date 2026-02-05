# Environment-Specific Values

This directory contains environment-specific Helm values files for CloudNativePG PostgreSQL clusters.

## Structure

```
environments/
├── local/
│   ├── dev.yaml      # Local development (1 instance, minimal resources)
│   ├── qa.yaml       # Local QA (2 instances, moderate resources)
│   └── prod.yaml     # Local production (3 instances, production resources)
└── cloud/
    ├── dev.yaml      # Cloud development (2 instances, cloud storage)
    ├── qa.yaml       # Cloud QA (2 instances, increased resources)
    └── prod.yaml     # Cloud production (3 instances, full HA)
```

## Usage

### With Helm CLI

```bash
# From apps/data/cnpg directory
helm upgrade --install platform-postgres-dev . \
  --namespace data-dev \
  --create-namespace \
  --values values.yaml \
  --values environments/local/dev.yaml
```

### With Argo CD UI

When creating an Application in Argo CD UI:

1. **Path**: `apps/data/cnpg`
2. **Values Files**: 
   - `values.yaml`
   - `environments/local/dev.yaml`

### With kubectl (Argo CD Application)

```bash
kubectl apply -f apps/data/cnpg/argocd/clusters/local/dev.yaml
```

## Configuration

Each environment file contains:

- **Cluster configuration**: instances, resources, storage
- **PostgreSQL tuning**: connection limits, memory settings
- **SealedSecret**: encrypted credentials (username, password)
- **Environment labels**: for identification and organization

## Encrypted Secrets

All environment files include SealedSecret configuration with encrypted credentials:

```yaml
sealedSecret:
  enabled: true
  name: platform-postgres-app
  encryptedData:
    username: "AgA..."  # Encrypted with kubeseal
    password: "AgB..."  # Encrypted with kubeseal
```

To encrypt secrets:

```bash
echo -n "your-value" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace data-dev \
  --name platform-postgres-app
```

See `docs/SEALED-SECRETS-GUIDE.md` for detailed instructions.

## Environment Comparison

### Local Environments (Longhorn storage)

| File | Namespace | Instances | CPU/Memory | Storage |
|------|-----------|-----------|------------|---------|
| local/dev.yaml | data-dev | 1 | 250m/512Mi | 20Gi |
| local/qa.yaml | data-qa | 2 | 500m/1Gi | 30Gi |
| local/prod.yaml | data-prod | 3 | 1/2Gi | 50Gi |

### Cloud Environments (Cloud storage)

| File | Namespace | Instances | CPU/Memory | Storage |
|------|-----------|-----------|------------|---------|
| cloud/dev.yaml | data-dev | 2 | 500m/1Gi | 50Gi |
| cloud/qa.yaml | data-qa | 2 | 1/2Gi | 75Gi |
| cloud/prod.yaml | data-prod | 3 | 2/4Gi | 200Gi |

## Customization

To customize an environment:

1. Edit the appropriate values file
2. Modify cluster configuration as needed
3. Update encrypted secrets if changing credentials
4. Commit and push changes
5. Argo CD will automatically sync (if enabled)

## References

- [Main Chart README](../README.md)
- [Sealed Secrets Guide](../../../docs/SEALED-SECRETS-GUIDE.md)
- [Argo CD Applications](../argocd/README.md)
