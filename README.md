# toolsuite-platform-gitops

GitOps repository to bootstrap a **local-first** and **cloud-ready** Kubernetes platform, designed for:
- Advanced homelabs (k3s / multi-arch)
- Hybrid production environments (on-prem + cloud)
- Third-party reuse (public repos, no mandatory cloud services)

This repo prioritizes:
- **Zero cloud cost in early phases** (no RDS/managed services required)
- **Portability** (same manifests, different overlays)
- **Repeatability** (GitOps with Argo CD)
- **Multi-arch compatibility** (arm64 + amd64)

> Note: “edge” exposure (Ingress/Gateway/Cloudflare Tunnel) is intentionally deferred. Early access can be via internal networking / port-forward.

---

## Core stack

- GitOps: **Argo CD**
- Package Management: **Helm 3** (official CloudNativePG charts)
- CI: **GitHub Actions** (or Argo Workflows)
- Distributed block storage: **Longhorn**
- HA PostgreSQL in Kubernetes: **CloudNativePG (CNPG)**
- SSO / IAM: **Keycloak**
- Secrets for public repos: **Sealed Secrets**
- Networking/CNI: **Flannel** (k3s default) or Cilium

Typical lab infrastructure:
- Local Kubernetes via **k3s**
- Workers on **Proxmox** VMs (or other hypervisor)
- arm64 nodes (Raspberry Pi 4/5) + amd64 nodes (VMs/hosts)

---

## Repository goals

1. **Fast bootstrap**: get core platform components running locally without cloud dependencies.
2. **Production path**: scale replicas/resources and harden operations without rewriting everything.
3. **Local ↔ cloud portability**: mostly switch `overlays`/values, not the architecture.
4. **Multi-tenant-friendly**: Keycloak is intended to follow a “one realm per customer” approach.

---

## Repository layout

### Currently Implemented (Helm-based)

```text
.
├─ apps/
│  ├─ platform/              # Platform infrastructure (deploy once per cluster)
│  │  └─ cnpg-operator/      # CloudNativePG operator (Helm chart)
│  │     ├─ Chart.yaml       # Helm chart with official CNPG operator dependency
│  │     ├─ values.yaml      # Operator configuration
│  │     ├─ argocd/          # Argo CD Application manifests
│  │     │  └─ operator.yaml
│  │     └─ README.md
│  └─ data/                  # Data layer components
│     └─ cnpg/               # PostgreSQL cluster resources (Helm chart)
│        ├─ Chart.yaml       # Helm chart with official CNPG cluster dependency
│        ├─ values.yaml      # Base cluster configuration (shared)
│        ├─ templates/       # Helm templates (SealedSecret, etc.)
│        ├─ environments/    # Environment-specific values
│        │  ├─ local/        # Local environments (dev.yaml, qa.yaml, prod.yaml)
│        │  └─ cloud/        # Cloud environments (dev.yaml, qa.yaml, prod.yaml)
│        ├─ argocd/          # Argo CD Application manifests
│        │  └─ clusters/
│        │     ├─ local/     # Local cluster Applications
│        │     └─ cloud/     # Cloud cluster Applications
│        └─ README.md
└─ clusters/
   ├─ local/                 # Local k3s deployments (reference only)
   │  ├─ dev/                # Development environment
   │  │  ├─ secrets/         # Secret examples (deprecated, use values in chart)
   │  │  └─ README.md        # Reference documentation
   │  ├─ qa/
   │  └─ prod/
   └─ cloud/                 # Cloud deployments (reference only)
      ├─ dev/
      ├─ qa/
      └─ prod/
```

> **Migration Note:** This repository uses Helm charts with the official CloudNativePG charts. All configurations are self-contained within chart directories. See `docs/MIGRATION.md` for migration history.

### Planned

```text
.
├─ bootstrap/
│  └─ argocd/                # Minimal Argo CD install to start GitOps
├─ apps/
│  ├─ platform/              # Argo, sealed-secrets, etc.
│  ├─ security/              # Keycloak and security components
│  └─ observability/         # Metrics/logs/tracing
└─ docs/
   ├─ README.md              # Documentation index
   ├─ MIGRATION.md           # Migration guide
   ├─ SEALED-SECRETS-GUIDE.md
   ├─ migration/             # Migration history
   └─ guides/                # Deployment and troubleshooting guides
```

## Environment Strategy

Each environment (dev/qa/prod) is available in both **local** and **cloud** variants:

- **local/dev**: Single instance, minimal resources (250m CPU, 512Mi RAM) → namespace: `data-dev`
- **local/qa**: 2 instances, moderate resources (500m CPU, 1Gi RAM) → namespace: `data-qa`
- **local/prod**: 3 instances, production resources (1 CPU, 2Gi RAM) → namespace: `data-prod`
- **cloud/dev**: 2 instances, cloud storage (500m CPU, 1Gi RAM) → namespace: `data-dev`
- **cloud/qa**: 2 instances, increased resources (1 CPU, 2Gi RAM) → namespace: `data-qa`
- **cloud/prod**: 3 instances, HA setup (2 CPU, 4Gi RAM) → namespace: `data-prod`

All environments use Helm values files to customize the base chart configuration in `apps/data/cnpg/environments/`

### Namespace Management

Each environment deploys to its own namespace using automatic namespace transformation:
- **Dev environments** → `data-dev`
- **QA environments** → `data-qa`
- **Production environments** → `data-prod`

This allows multiple environments to coexist in the same cluster if needed, with proper isolation and RBAC boundaries.

### Secrets Management

Secrets are managed through Helm values files using Bitnami Sealed Secrets:

1. **Encrypt your secrets** using kubeseal:
   ```bash
   echo -n "your-password" | kubeseal --raw \
     --from-file=/dev/stdin \
     --namespace data-dev \
     --name platform-postgres-app
   ```

2. **Add encrypted values** to environment's `values.yaml`:
   ```yaml
   sealedSecret:
     enabled: true
     encryptedData:
       username: "AgA..."  # Encrypted value
       password: "AgB..."  # Encrypted value
   ```

3. **Commit to Git** - Encrypted values are safe to commit

4. **Deploy via Argo CD** - Secrets are automatically created with the cluster

See `docs/SEALED-SECRETS-GUIDE.md` for detailed instructions and troubleshooting.

## Deployment Order

### 1. Deploy Platform Infrastructure (Once per Cluster)

```bash
# Update Helm dependencies
cd apps/platform/cnpg-operator
helm dependency update

# Deploy CNPG operator
helm upgrade --install cnpg-operator . \
  --namespace cnpg-system \
  --create-namespace \
  --values values.yaml

# Verify operator is running
kubectl get pods -n cnpg-system
```

### 2. Encrypt and Configure Secrets

Secrets are now managed through Helm values files. Encrypt your secrets and add them to the environment's values file:

```bash
# Encrypt username
echo -n "platform" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace data-dev \
  --name platform-postgres-app

# Encrypt password
echo -n "your-strong-password" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace data-dev \
  --name platform-postgres-app

# Update apps/data/cnpg/environments/local/dev.yaml with the encrypted values:
# sealedSecret:
#   enabled: true
#   encryptedData:
#     username: "AgA..."  # Your encrypted username
#     password: "AgB..."  # Your encrypted password

# Commit to Git
git add apps/data/cnpg/environments/local/dev.yaml
git commit -m "Add encrypted secrets for local dev"
git push
```

See `docs/SEALED-SECRETS-GUIDE.md` for detailed instructions.

### 3. Deploy PostgreSQL Clusters

```bash
# Update Helm dependencies
cd apps/data/cnpg
helm dependency update

# Deploy to your chosen environment (includes secrets)
# Local dev example:
helm upgrade --install platform-postgres-dev . \
  --namespace data-dev \
  --create-namespace \
  --values values.yaml \
  --values environments/local/dev.yaml

# The deployment will create both the cluster and the SealedSecret
# The sealed-secrets controller will automatically unseal it

# Or use Argo CD (recommended for GitOps)
kubectl apply -f apps/data/cnpg/argocd/clusters/local/dev.yaml
```

**Important:** The CNPG operator must be deployed before any PostgreSQL clusters.

### Using Argo CD (Recommended)

For GitOps deployments, use the Argo CD Application manifests:
- Operator: `apps/platform/cnpg-operator/argocd/operator.yaml`
- Clusters: `apps/data/cnpg/argocd/clusters/{local|cloud}/{env}.yaml`

All manifests are self-contained within their respective chart directories.

See `docs/guides/deployment.md` for detailed deployment instructions.

### Environment Selection

To deploy to different environments, use the corresponding values file:
- **Local dev:** `environments/local/dev.yaml`
- **Local QA:** `environments/local/qa.yaml`
- **Local prod:** `environments/local/prod.yaml`
- **Cloud dev:** `environments/cloud/dev.yaml`
- **Cloud QA:** `environments/cloud/qa.yaml`
- **Cloud prod:** `environments/cloud/prod.yaml`

Each values file is located in `apps/data/cnpg/environments/` and configures the appropriate namespace, resources, and storage class.

## Documentation

Comprehensive documentation is available in the `docs/` directory:

- **[Documentation Index](docs/README.md)** - Complete documentation overview
- **[Deployment Guide](docs/guides/deployment.md)** - Step-by-step deployment instructions
- **[Troubleshooting Guide](docs/guides/troubleshooting.md)** - Common issues and solutions
- **[Sealed Secrets Guide](docs/SEALED-SECRETS-GUIDE.md)** - Managing secrets securely
- **[Migration Guide](docs/MIGRATION.md)** - Kustomize to Helm migration details

## Contributing
