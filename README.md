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
   ├─ local/                 # k3s/local overlay (Longhorn, low resources)
   └─ cloud/                 # Cloud overlay (scaffold with examples)
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
