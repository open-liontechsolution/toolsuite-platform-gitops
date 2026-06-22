# internal-ca

Self-signed **internal CA** built on cert-manager, for private services that are only
reachable inside the home network (e.g. `*.casa.lan`). Public ACME/Let's Encrypt cannot
issue for a non-public domain, so internal TLS is signed by this CA instead.

Deployed once per cluster (platform tier, Argo CD project `default`).

## Chain

`selfsigned-bootstrap` (selfSigned ClusterIssuer) → `casa-internal-ca-root` (root CA
Certificate, secret in `cert-manager`) → `casa-internal-ca` (CA ClusterIssuer).

## Use it

Reference the CA issuer from any consumer:

```yaml
annotations:
  cert-manager.io/cluster-issuer: casa-internal-ca
```

Used by:
- **Authentik UI** ingress (`apps/security/authentik`, host `authentik.casa.lan`).
- **LDAPS outpost** (Fase 2) — clients (browsers, Bazzite/SSSD) must trust the CA.

## Distribute the CA to clients

```bash
kubectl -n cert-manager get secret casa-internal-ca-root -o jsonpath='{.data.ca\.crt}' | base64 -d > casa-internal-ca.crt
```

Install `casa-internal-ca.crt` in each client's trust store (browser, and the Bazzite system
trust store — handled in the kxs-ansible repo). This is the brief's "CA de confianza en
clientes" requirement for LDAPS.

## Prerequisites

cert-manager must already be installed (`apps/platform/cert-manager`).

## Validate locally

```bash
helm template internal-ca . -f values.yaml
helm lint . -f values.yaml
```
