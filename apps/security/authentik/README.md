# authentik

**Authentik** as the centralized **family Identity Provider** — completely independent
from Keycloak (`apps/security/keycloak`). Different release, different workloads, no
federation. Keycloak is **not** touched.

Wraps the upstream `authentik` chart (`2026.5.3`).

## What this chart deploys

- Authentik **server** + **worker** (subchart), pinned to `worker` nodes (arm64).
- A **dedicated Redis** (`templates/redis.yaml`) — the upstream chart no longer bundles
  Redis. Dev = single instance with a Longhorn PVC. **Decision:** in-cluster plain Redis
  (no auth, protected by namespace + NetworkPolicy) keeps moving parts minimal; for prod,
  switch to a replicated Redis and add `AUTHENTIK_REDIS__PASSWORD`.
- A **SealedSecret** (`authentik-secret`) with `AUTHENTIK_SECRET_KEY`, the Postgres
  password, and bootstrap admin creds — injected via `authentik.global.env` (explicit
  `env` overrides the chart's generated config secret).
- An egress **NetworkPolicy** (DB, Redis, DNS, web), mirroring Keycloak's.
- A **blueprints ConfigMap** built from `blueprints/*.yaml` and mounted into the worker
  (`authentik.blueprints.configMaps: [authentik-blueprints]`), so config stays in git.
- A **LoadBalancer Service** (Cilium LB-IPAM/BGP, pinned `192.169.2.40`) exposing the UI —
  Cilium Ingress is not functional in this cluster and Gateway API is not enabled. Authentik
  terminates TLS on `:9443` with a `casa-internal-ca` cert (`templates/certificate.yaml`),
  mounted into `/certs` and discovered, then assigned to the `authentik.casa.lan` brand by
  `blueprints/10-brand-web-cert.yaml`. Point DNS `authentik.casa.lan` → `192.169.2.40`.

## External dependencies (deploy first)

1. CNPG operator — `apps/platform/cnpg-operator`.
2. Authentik Postgres — `apps/data/authentik-postgres` (provides
   `authentik-postgres-casa-rw.data-casa.svc`).
3. Controllers already in-cluster: `sealed-secrets`, `cert-manager`, Cilium ingress + LB-IPAM.

## Secrets

**Easy path** — fill a git-ignored plaintext file and run the helper, which seals every
value and writes the ciphertext into both `casa.yaml` files (DB password kept consistent
across the two namespaces):

```bash
cp scripts/authentik-secrets.env.example scripts/authentik-secrets.env   # fill it in (git-ignored)
KUBECONFIG=~/.kube/k3slocal.yaml ./scripts/seal-authentik.sh
```

**Manual path** — seal each value yourself:

```bash
echo -n "$(openssl rand -base64 60)" | kubeseal --raw --from-file=/dev/stdin --namespace security-casa --name authentik-secret --controller-name sealed-secrets --controller-namespace kube-system  # AUTHENTIK_SECRET_KEY
echo -n "<db-pass>"  | kubeseal --raw --from-file=/dev/stdin --namespace security-casa --name authentik-secret --controller-name sealed-secrets --controller-namespace kube-system  # AUTHENTIK_POSTGRESQL__PASSWORD (== CNPG app secret)
echo -n "<admin-pw>" | kubeseal --raw --from-file=/dev/stdin --namespace security-casa --name authentik-secret --controller-name sealed-secrets --controller-namespace kube-system  # AUTHENTIK_BOOTSTRAP_PASSWORD
echo -n "<api-tok>"  | kubeseal --raw --from-file=/dev/stdin --namespace security-casa --name authentik-secret --controller-name sealed-secrets --controller-namespace kube-system  # AUTHENTIK_BOOTSTRAP_TOKEN
```
Paste the ciphertext under `sealedSecret.encryptedData.*` in `environments/local/casa.yaml`.

## Before syncing

- Deploy `apps/platform/internal-ca` first (provides ClusterIssuer `casa-internal-ca`).
- Seal the secrets (see above) and import the internal CA into client trust stores so
  `https://authentik.casa.lan` is trusted.

## Validate locally

```bash
helm dependency build
helm template authentik-casa . -f values.yaml -f environments/local/casa.yaml
helm lint . -f values.yaml -f environments/local/casa.yaml
```

## Acceptance (Fase 1)

UI answers over HTTPS; worker system tasks green; pod restarts keep state; a Pi node
failover reschedules server/worker.

## Next: Fase 2 (LDAP + OIDC/SAML) — partially scaffolded here

`blueprints/00-family-groups.yaml` creates the base groups (`familia`, `adultos`,
`menores`, `pc-salon`, `pc-estudio`). Still **TODO** as blueprints (do after the core is
running and the schema is verified against `2026.5.3`):

- **LDAP Provider**: Base DN `DC=ldap,DC=casa,DC=lan`, **UID/GID start ≥ 5000** (avoid
  collision with Bazzite local users at 1000+), service account in the search group.
- **LDAP Outpost**: expose **LDAPS :636** via a `Service type: LoadBalancer` — the cluster
  has Cilium LB-IPAM (`blue-pool` 192.169.2.0/24). Cert signed by `casa-internal-ca`
  (`apps/platform/internal-ca`); the same CA is trusted by SSSD clients.
- **OIDC + SAML** Applications/Providers for ChromeOS/Android (Fase 6 web side).

The host-level consumers of this IdP (Bazzite/SSSD, NFS home roaming, parental controls)
live in the **`kxs-ansible`** repo, not here.
