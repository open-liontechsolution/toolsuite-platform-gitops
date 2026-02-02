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

- GitOps: :contentReference[oaicite:0]{index=0}
- CI: :contentReference[oaicite:1]{index=1}
- Distributed block storage: :contentReference[oaicite:2]{index=2}
- HA PostgreSQL in Kubernetes: :contentReference[oaicite:3]{index=3}
- SSO / IAM: :contentReference[oaicite:4]{index=4}
- Secrets for public repos: :contentReference[oaicite:5]{index=5}
- Networking/CNI: :contentReference[oaicite:6]{index=6}

Typical lab infrastructure:
- Local Kubernetes via :contentReference[oaicite:7]{index=7}
- Workers on :contentReference[oaicite:8]{index=8} VMs
- arm64 nodes (Raspberry Pi 4/5) + amd64 nodes (VMs/hosts)

---

## Repository goals

1. **Fast bootstrap**: get core platform components running locally without cloud dependencies.
2. **Production path**: scale replicas/resources and harden operations without rewriting everything.
3. **Local ↔ cloud portability**: mostly switch `overlays`/values, not the architecture.
4. **Multi-tenant-friendly**: Keycloak is intended to follow a “one realm per customer” approach.

---

## Repository layout (proposed)

```text
.
├─ bootstrap/
│  └─ argocd/                # minimal Argo CD install to start GitOps
├─ apps/
│  ├─ platform/              # argo, sealed-secrets, etc.
│  ├─ data/                  # longhorn, cnpg, backups
│  ├─ security/              # keycloak and security components
│  └─ observability/         # (future) metrics/logs/tracing
├─ clusters/
│  ├─ local/                 # k3s/local overlay (storageClass, node selectors, low resources)
│  └─ cloud/                 # cloud overlay (cloud storageClass, resources, etc.)
└─ docs/
   ├─ quickstart.md
   ├─ operations.md
   └─ decisions/             # ADRs (Architecture Decision Records)
