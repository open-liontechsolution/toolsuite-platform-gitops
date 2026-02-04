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

### Currently Implemented

```text
.
├─ apps/
│  └─ data/                  # Data layer components
│     └─ cnpg/               # CloudNativePG operator and PostgreSQL cluster
└─ clusters/
   ├─ local/                 # Local k3s deployments (Longhorn storage)
   │  ├─ dev/                # Development environment (1 instance, minimal resources)
   │  ├─ qa/                 # QA environment (2 instances, moderate resources)
   │  └─ prod/               # Production environment (3 instances, high resources)
   └─ cloud/                 # Cloud deployments (EKS/GKE/AKS)
      ├─ dev/                # Development environment (2 instances)
      ├─ qa/                 # QA environment (2 instances, more resources)
      └─ prod/               # Production environment (3 instances, HA setup)
```

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

All environments use Kustomize overlays to customize the base manifests in `apps/`

### Namespace Management

Each environment deploys to its own namespace using automatic namespace transformation:
- **Dev environments** → `data-dev`
- **QA environments** → `data-qa`
- **Production environments** → `data-prod`

This allows multiple environments to coexist in the same cluster if needed, with proper isolation and RBAC boundaries.

### Secrets Management

Each environment must have its own sealed secret:

1. Copy the example: `cp apps/data/cnpg/secret-app.example.yaml clusters/local/dev/secret-app.yaml`
2. Edit and set a strong password
3. Encrypt: `kubeseal --format=yaml --namespace data-dev < secret-app.yaml > sealedsecret-app.yaml`
4. Uncomment the secret reference in the environment's `kustomization.yaml`
5. Delete the plain secret file

See individual environment READMEs for detailed instructions
