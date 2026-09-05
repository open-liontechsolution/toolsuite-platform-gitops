# platform-postgres — Postgres general del tier de PRODUCCION

Cluster CloudNativePG que aloja **todas** las bases de produccion del cluster k3s.
Wrapper del chart oficial `cloudnative-pg/cluster`, desplegado por Argo CD.

| Entorno | Application | Release | Namespace | Instancias | Almacenamiento |
|---|---|---|---|---|---|
| `local/prod` | `platform-postgres-local-prod` | `platform-postgres-prod` | `data-prod` | 1 | 20Gi + 1Gi WAL (longhorn) |

## Que aloja

| Base | Role dueno | Quien la usa | Como esta declarada |
|---|---|---|---|
| `keycloak_prod` | `keycloak_prod` | Keycloak de produccion (`security-prod`) | `cluster.cluster.initdb` |
| `deal_tracker_prod` | `deal_tracker_prod` | deal-tracker produccion (`deal-tracker-prod`) | `cluster.databases` + `cluster.cluster.roles` + `roleSecrets` |
| `helit` | `helit` | helit produccion — la despensa de la familia (`helit-prod`) | igual que la anterior |

**Las tres estan declaradas**, que es la diferencia con `platform-postgres-dev`: alli
cinco de siete bases se crearon a mano y no viven en ningun repositorio (ver
`apps/data/cnpg/README.md`). Aqui reconstruir el cluster desde cero reproduce el
reparto completo de bases, duenos y roles.

`helit` llega vacia y se rellena en la ventana del corte
(juanjocop/cocina-familiar#22) con un `pg_dump` de la base `cocina` de
`platform-postgres-dev`, que es donde vivia. Se declara aqui **antes** de la ventana a
proposito: primero el role, despues el `DATABASE_URL` sellado del otro repo, por lo que
dice `apps/data/cnpg/environments/local/dev.yaml` sobre los 40 minutos en
CrashLoopBackOff.

La crea el CRD `Database`, no un `CREATE DATABASE` a mano, y eso basta para el
*collation*: `template1` de este cluster ya es `C`/`C`/`UTF8`, que es de lo que depende
el plegado de `normaliza()` en la app.

### Por que el initdb es el del IdP

`initdb` da UNA base y su role, y en este cluster general podria haber sido una neutra
tipo `platform`. Es la del IdP porque cuando se hizo el traslado de la #71 sus
credenciales ya estaban selladas **dos veces** —aqui bajo `sealedSecret` y contra
`security-prod` bajo `KC_DB_PASSWORD`— y reaprovecharlas dejo el movimiento del Keycloak
en un solo valor a re-sellar, `KC_DB_URL_HOST`.

Consecuencia para quien venga: **el resto de inquilinos no entran por ahi**. Se declaran
en `cluster.databases` + `cluster.cluster.roles` + `roleSecrets`, como `deal_tracker_prod`.

## Anadir un inquilino

Tres piezas, en el mismo commit (el procedimiento largo y sus trampas estan en
`apps/data/cnpg/README.md`):

```yaml
cluster:
  cluster:
    roles:                       # ojo: cluster.cluster.roles, NO cluster.managed.roles
      - name: mi_app
        ensure: present
        login: true
        superuser: false
        createdb: false
        passwordSecret:
          name: mi-app-db
        inherit: true            # default del API server, escrito a mano a proposito
        connectionLimit: -1      # idem
  databases:                     # hermana de cluster.cluster, no dentro
    - name: mi_app
      owner: mi_app
      databaseReclaimPolicy: retain

roleSecrets:
  mi-app-db:
    username: "<ciphertext de: mi_app>"
    password: "<ciphertext>"
```

- El `username` sellado tiene que ser **literalmente** el nombre del role: CNPG lo
  compara y si no cuadra ignora la contrasena sin avisar.
- `inherit` y `connectionLimit` van escritos aunque sean defaults: Argo posee
  `spec.managed.roles` como lista **atomica** y sin ellos la Application se queda
  `OutOfSync` para siempre (#55).
- `retain` explicito: con `delete`, borrar el objeto `Database` **DROPea la base**.
- Declarar un role que **ya existe** con `passwordSecret` hace que CNPG le **resetee la
  contrasena** a la sellada. Los preexistentes se adoptan de uno en uno.

## Historia: de donde sale este chart

Es `apps/data/keycloak-postgres` renombrado, no un cluster nuevo de cero. Aquel chart
(#62) monto un CNPG dedicado al IdP de produccion siguiendo el precedente de
`apps/data/authentik-postgres` — uno por inquilino. La #71 reviso esa decision antes de
que hubiera tres clusters y fijo la contraria: **uno por tier**. Como el nombre de un
`Cluster` de CNPG esta grabado en PVCs, Services y secretos, renombrarlo fue crear este
y trasladarle las dos bases con `pg_dump`/`pg_restore`.

Lo que se acepta a cambio, escrito para que no se redescubra: el restore de CNPG es **del
cluster entero, no de una base**, asi que un PITR pedido por el IdP se lleva por delante
los datos de la aplicacion y al reves. Es mucho menos grave que lo que se cierra —antes
`deal_tracker_prod` compartia pod con dev y QA— pero no es cero.

## Backups

`barmanObjectStore` -> MinIO (`s3://cnpg-backup/platform-postgres-prod/`), 02:15 UTC,
retencion 30d. Escalonado respecto a `platform-postgres-dev` (01:30) y
`authentik-postgres-casa` (01:45): los tres suben por la misma LAN.

La credencial la gobierna `kxs-ansible` (`roles/minio_creds`), **no se sella a mano**.

**`ContinuousArchiving: True` no prueba nada**: CNPG arranca con `archive_mode=on`
siempre. Lo que lo prueba, en orden:

```bash
kubectl -n data-prod get secret cnpg-backup-s3-creds
kubectl -n data-prod get backups.postgresql.cnpg.io      # PHASE=completed, ERROR vacio
kubectl -n data-prod get cluster platform-postgres-prod \
  -o jsonpath='{.status.firstRecoverabilityPoint}{"\n"}{.status.lastSuccessfulBackup}'
```

(`kubectl get backup` a secas resuelve a `backup.longhorn.io`, que es otra cosa.)

## Monitorizacion

`cluster.monitoring.*` se queda en `false`: el PodMonitor y las alert rules son de
`k3s-local-apps-manifests`. **Su `namespaceSelector` cubre `data-dev` y `data-casa`, asi
que este cluster no se scrapea** hasta que se anada `data-prod` alli.

## Alta disponibilidad

`instances: 1`. La `nodeAffinity` exige `worker=true` **AND** `performance=high`, y
`worker4` es el unico nodo que lo cumple (`master1` lleva la etiqueta pero es
control-plane). Un segundo pod quedaria `Pending`. Para HA real hay que etiquetar otro
worker desde `kxs-ansible` o relajar la affinity a `preferred`.
