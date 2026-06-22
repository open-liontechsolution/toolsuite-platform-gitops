# authentik-postgres

Dedicated **CloudNativePG** PostgreSQL cluster for **Authentik** (the family IdP).
Separate from `apps/data/cnpg` (`platform-postgres`) so the Authentik database is
isolated, as required by the project brief.

Wraps the upstream `cluster` chart (`0.6.1`) — same pattern as `apps/data/cnpg`.

## Layout

| File | Purpose |
|------|---------|
| `Chart.yaml` | Pins the `cluster` subchart. |
| `values.yaml` | Base config (db/owner `authentik`, secret `authentik-postgres-app`). |
| `environments/local/casa.yaml` | `casa` overlay (1 instance, Longhorn, worker/`performance=high` affinity). |
| `templates/sealedsecret.yaml` | `SealedSecret` with the DB `username`/`password`. |
| `argocd/clusters/local/casa.yaml` | Argo CD Application (`project: tools`, ns `data-casa`). |

## Deployment order

CNPG operator (`apps/platform/cnpg-operator`) **must** exist first. Then this cluster,
then `apps/security/authentik`.

## Secrets

The DB password is shared with Authentik. Seal the **same plaintext** into two places:

```bash
# 1) this cluster's app secret (namespace data-casa)
echo -n "authentik" | kubeseal --raw --from-file=/dev/stdin --namespace data-casa --name authentik-postgres-app --controller-name sealed-secrets --controller-namespace kube-system   # -> username
echo -n "<db-pass>" | kubeseal --raw --from-file=/dev/stdin --namespace data-casa --name authentik-postgres-app --controller-name sealed-secrets --controller-namespace kube-system   # -> password

# 2) Authentik's secret (namespace security-casa), key AUTHENTIK_POSTGRESQL__PASSWORD
echo -n "<db-pass>" | kubeseal --raw --from-file=/dev/stdin --namespace security-casa --name authentik-secret --controller-name sealed-secrets --controller-namespace kube-system
```

Paste the ciphertext into `environments/local/casa.yaml` (`sealedSecret.encryptedData`)
here and in `apps/security/authentik/environments/local/casa.yaml`.

## Validate locally

```bash
helm dependency build
helm template authentik-postgres-casa . -f values.yaml -f environments/local/casa.yaml
helm lint . -f values.yaml -f environments/local/casa.yaml
```
