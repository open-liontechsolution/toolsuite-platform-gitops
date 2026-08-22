# keycloak-postgres

Cluster **CloudNativePG** dedicado al **Keycloak de produccion** (issue #62).

Separado de `apps/data/cnpg` (`platform-postgres-dev`) a proposito: la mitad del problema que cierra
la #62 es que el login de produccion depende hoy de infraestructura de dev. Mover el IdP a su propia
instancia y dejarle la base en el cluster de datos de dev habria movido el pod, no la dependencia.

Envuelve el chart upstream `cluster` (`0.6.1`) — mismo patron que `apps/data/cnpg` y que
`apps/data/authentik-postgres`, que es el precedente exacto: un CNPG dedicado a un solo IdP.

## Estructura

| Fichero | Para que |
|---|---|
| `Chart.yaml` | Fija la version del subchart `cluster`. |
| `values.yaml` | Base (db/owner `keycloak_prod`, secret `keycloak-postgres-app`, backup a MinIO apagado). |
| `environments/local/prod.yaml` | Overlay `prod` (1 instancia, Longhorn, affinity worker + `performance=high`). |
| `templates/sealedsecret.yaml` | `SealedSecret` con `username`/`password` de la base. |
| `templates/backup-s3-sealedsecret.yaml` | `SealedSecret` con la credencial S3 del backup a MinIO. |
| `argocd/clusters/local/prod.yaml` | Application de Argo CD (`project: tools`, ns `data-prod`). |

## Orden de despliegue

El operator de CNPG (`apps/platform/cnpg-operator`) tiene que existir **antes**. Despues este
cluster, y solo despues `apps/security/keycloak` con `environments/local/prod.yaml`.

## Secretos

La contrasena de la base la usan dos namespaces, asi que va sellada **dos veces con el mismo
plaintext** — un SealedSecret va atado a namespace + nombre y los ciphertexts salen distintos:

```bash
# 1) el secret de esta base (ns data-prod)
echo -n "keycloak_prod" | kubeseal --raw --from-file=/dev/stdin \
  --namespace data-prod --name keycloak-postgres-app \
  --controller-name sealed-secrets --controller-namespace kube-system   # -> username
echo -n "<db-pass>"     | kubeseal --raw --from-file=/dev/stdin \
  --namespace data-prod --name keycloak-postgres-app \
  --controller-name sealed-secrets --controller-namespace kube-system   # -> password

# 2) el secret de Keycloak (ns security-prod), clave KC_DB_PASSWORD
echo -n "<db-pass>"     | kubeseal --raw --from-file=/dev/stdin \
  --namespace security-prod --name keycloak-admin-credentials \
  --controller-name sealed-secrets --controller-namespace kube-system
```

El primero va en `environments/local/prod.yaml` de aqui; el segundo en
`apps/security/keycloak/environments/local/prod.yaml`. **Si se rota, se rotan los dos en el mismo
commit**: si divergen, Keycloak no arranca y el error que da es de autenticacion contra Postgres.

### La credencial del backup no se sella a mano

`cnpg-backup-s3-creds` es la credencial del usuario `cnpg-backup` de MinIO, la misma que usan
`platform-postgres-dev` y `authentik-postgres-casa`. El bucket, la policy, el usuario y el plaintext
los gobierna **`juanjocop/kxs-ansible`** (`roles/minio_creds`, `playbooks/minio_creds.yml`, vault
cifrado; procedimiento en su `docs/MINIO_CREDS.md`).

Para tener el ciphertext de `data-prod` hay que anadir el destino a `minio_seal_targets` de ese rol
y ejecutar el playbook: deja los dos valores en su `out/cnpg-backup-s3-creds.yaml`. Crear
credenciales de MinIO por fuera de ese camino es exactamente como `longhorn-backup` costo 49 dias de
backup roto sin que saltara nada.

Mientras ese ciphertext no este, `backups.enabled` y `backupSecret.enabled` se quedan en `false`.
**Los dos flags se encienden juntos y en el mismo commit que los ciphertexts**: con
`backups.enabled` y sin Secret, el cluster arranca igual y lo unico que falla es el archivado de
WAL — o sea que el fallo no se ve hasta el dia que hace falta el backup.

## Monitorizacion

`monitoring.podMonitor.enabled` y `prometheusRule.enabled` se quedan en **false**: esos objetos son
del repo `k3s-local-apps-manifests`. Y ojo — su PodMonitor lleva un `namespaceSelector` sobre
`data-dev` y `data-casa`, asi que **este cluster no se scrapea** hasta que se anada `data-prod`
alli. Es un cambio de aquel repo.

## Verificar

```bash
kubectl -n data-prod get cluster keycloak-postgres-prod
kubectl -n data-prod get pods -l cnpg.io/cluster=keycloak-postgres-prod
# el archivado de WAL no se ve en que el pod arranque, sino aqui:
kubectl -n data-prod get cluster keycloak-postgres-prod \
  -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")]}'
```
