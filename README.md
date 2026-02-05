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
│  │     └─ kustomize-deprecated/  # Old Kustomize files (deprecated)
│  └─ data/                  # Data layer components
│     └─ cnpg/               # PostgreSQL cluster resources (Helm chart)
│        ├─ Chart.yaml       # Helm chart with official CNPG cluster dependency
│        ├─ values.yaml      # Base cluster configuration (shared)
│        └─ kustomize-deprecated/ # Old Kustomize files (deprecated)
└─ clusters/
   ├─ local/                 # Local k3s deployments (Longhorn storage)
   │  ├─ dev/                # Development environment (1 instance, minimal resources)
   │  │  ├─ values.yaml      # Environment-specific Helm values
   │  │  ├─ secrets/         # Sealed secrets for this environment
   │  │  └─ README.md        # Deployment instructions
   │  ├─ qa/                 # QA environment (2 instances, moderate resources)
   │  │  ├─ values.yaml      # Environment-specific Helm values
   │  │  └─ secrets/
   │  └─ prod/               # Production environment (3 instances, high resources)
   │     ├─ values.yaml      # Environment-specific Helm values
   │     └─ secrets/
   └─ cloud/                 # Cloud deployments (EKS/GKE/AKS)
      ├─ dev/                # Development environment (2 instances)
      │  ├─ values.yaml      # Environment-specific Helm values
      │  └─ secrets/
      ├─ qa/                 # QA environment (2 instances, more resources)
      │  ├─ values.yaml      # Environment-specific Helm values
      │  └─ secrets/
      └─ prod/               # Production environment (3 instances, HA setup)
         ├─ values.yaml      # Environment-specific Helm values
         └─ secrets/
```

> **Migration Note:** This repository has migrated from Kustomize to Helm charts using the official CloudNativePG charts. Previous Kustomize configurations are preserved in `kustomize-deprecated/` folders. See `MIGRATION.md` for details.

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
   ├─ quickstart.md
   ├─ operations.md
   └─ decisions/             # ADRs (Architecture Decision Records)
```

## Environment Strategy

Each environment (dev/qa/prod) is available in both **local** and **cloud** variants:

- **local/dev**: Single instance, minimal resources (250m CPU, 512Mi RAM) → namespace: `data-dev`
- **local/qa**: 2 instances, moderate resources (500m CPU, 1Gi RAM) → namespace: `data-qa`
- **local/prod**: 3 instances, production resources (1 CPU, 2Gi RAM) → namespace: `data-prod`
- **cloud/dev**: 2 instances, cloud storage (500m CPU, 1Gi RAM) → namespace: `data-dev`
- **cloud/qa**: 2 instances, increased resources (1 CPU, 2Gi RAM) → namespace: `data-qa`
- **cloud/prod**: 3 instances, HA setup (2 CPU, 4Gi RAM) → namespace: `data-prod`

All environments use Helm values files to customize the base chart configuration in `apps/data/cnpg/`

### Namespace Management

Each environment deploys to its own namespace using automatic namespace transformation:
- **Dev environments** → `data-dev`
- **QA environments** → `data-qa`
- **Production environments** → `data-prod`

This allows multiple environments to coexist in the same cluster if needed, with proper isolation and RBAC boundaries.

### Secrets Management

Each environment must have its own sealed secret:

1. Copy the example: `cp clusters/local/dev/secrets/secret-app.example.yaml clusters/local/dev/secrets/secret-app.yaml`
2. Edit and set a strong password
3. Encrypt: `kubeseal --format=yaml --namespace data-dev < clusters/local/dev/secrets/secret-app.yaml > clusters/local/dev/secrets/sealedsecret-app.yaml`
4. Apply the sealed secret: `kubectl apply -f clusters/local/dev/secrets/sealedsecret-app.yaml`
5. Delete the plain secret file: `rm clusters/local/dev/secrets/secret-app.yaml`

See individual environment READMEs for detailed instructions

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

### 2. Create Application Secrets

```bash
# For each environment, create and seal the secret
cd clusters/local/dev
cp secrets/secret-app.example.yaml secrets/secret-app.yaml
# Edit secrets/secret-app.yaml and set a strong password

# Encrypt with kubeseal
kubeseal --format=yaml --namespace data-dev \
  < secrets/secret-app.yaml \
  > secrets/sealedsecret-app.yaml

# Apply the sealed secret
kubectl apply -f secrets/sealedsecret-app.yaml

# Delete the plain secret
rm secrets/secret-app.yaml
```

### 3. Deploy PostgreSQL Clusters

```bash
# Update Helm dependencies
cd apps/data/cnpg
helm dependency update

# Deploy to your chosen environment
# Local dev example:
helm upgrade --install platform-postgres-dev . \
  --namespace data-dev \
  --create-namespace \
  --values values.yaml \
  --values ../../clusters/local/dev/values.yaml

# Or use Argo CD (recommended for GitOps)
```

**Important:** The CNPG operator must be deployed before any PostgreSQL clusters.

### Using Argo CD (Recommended)

For GitOps deployments, create Argo CD Applications pointing to:
- Operator: `apps/platform/cnpg-operator`
- Clusters: `apps/data/cnpg` with appropriate values files

See `argocd/` directory for example Application manifests.

### Environment Selection

To deploy to different environments, use the corresponding values file:
- **Local dev:** `../../clusters/local/dev/values.yaml`
- **Local QA:** `../../clusters/local/qa/values.yaml`
- **Local prod:** `../../clusters/local/prod/values.yaml`
- **Cloud dev:** `../../clusters/cloud/dev/values.yaml`
- **Cloud QA:** `../../clusters/cloud/qa/values.yaml`
- **Cloud prod:** `../../clusters/cloud/prod/values.yaml`

Each values file is located in its respective environment directory and configures the appropriate namespace, resources, and storage class.
