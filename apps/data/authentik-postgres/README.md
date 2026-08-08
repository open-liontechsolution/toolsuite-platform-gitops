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
| `templates/backup-s3-sealedsecret.yaml` | `SealedSecret` con la credencial S3 del backup a MinIO. |
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

## Backups

Aquí vive el auth de casa: sin backup lógico, un `DROP TABLE` o una corrupción se lleva por delante los
usuarios de Authentik. Las 3 réplicas de Longhorn cubren perder un disco, no eso.

Misma configuración que `apps/data/cnpg` (MinIO `http://192.168.50.240:9000`, bucket `cnpg-backup`, retención
30 días, sin SSE), con el `ScheduledBackup` a las **01:45 UTC** para no solapar con el de `platform-postgres`
(01:30) — los dos suben al mismo host por la misma LAN. CNPG separa los dos clusters dentro del bucket por
`serverName`, así que la ruta acaba siendo `s3://cnpg-backup/authentik-postgres-casa/`.

El bucket, la policy y el usuario los gestiona `kxs-ansible` (`roles/minio_creds`,
[#47](https://github.com/juanjocop/kxs-ansible/pull/47)), no este repo. La credencial S3 es el **mismo
plaintext** que en `data-dev`, pero el ciphertext es distinto y no son intercambiables: un SealedSecret va
atado a namespace + nombre.

```bash
echo -n "<access-key>" | kubeseal --raw --from-file=/dev/stdin --namespace data-casa --name cnpg-backup-s3-creds --controller-name sealed-secrets --controller-namespace kube-system
echo -n "<secret-key>" | kubeseal --raw --from-file=/dev/stdin --namespace data-casa --name cnpg-backup-s3-creds --controller-name sealed-secrets --controller-namespace kube-system
```

Va a `backupSecret.encryptedData` de `environments/local/casa.yaml`. Ese `enabled` y el de
`cluster.backups.enabled` se encienden a la vez: con backups activos y sin Secret, el archivado de WAL falla y
el Cluster se queda con `ContinuousArchiving` en `False`. Al rotar hay que re-pegar en **los dos** ficheros
(`kxs-ansible/docs/MINIO_CREDS.md`).

Comprobación y detalle de restauración: `apps/data/cnpg/README.md`, sección Backups.

## HA

`instances: 1` a propósito. La `nodeAffinity` exige worker AND `performance=high` y `worker4` es el único
worker con esa etiqueta, así que un segundo pod se quedaría en `Pending`. La recuperación es por backup, no
por failover. Detalle en `apps/data/cnpg/README.md`.

## Monitoring

El PodMonitor que scrapea este cluster lo declara `k3s-local-apps-manifests`
(`prometheus/cnpg/podmonitor.yaml`, ns `monitoring`, con `namespaceSelector` sobre `data-casa`). Por eso
`cluster.monitoring.podMonitor.enabled` va a `false` aquí — encenderlo duplicaría el scrape.

## Validate locally

```bash
helm dependency build
helm template authentik-postgres-casa . -f values.yaml -f environments/local/casa.yaml
helm lint . -f values.yaml -f environments/local/casa.yaml
```
