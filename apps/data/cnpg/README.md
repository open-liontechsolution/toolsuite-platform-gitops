# CloudNativePG PostgreSQL Cluster (Helm Chart)

This component deploys the `platform-postgres` PostgreSQL cluster using the official CloudNativePG cluster
Helm chart, wrapped so that local config and the SealedSecrets live in this repo.

## Overview

The cluster chart uses the official [CloudNativePG cluster chart](https://github.com/cloudnative-pg/charts/tree/main/charts/cluster) as a dependency, with customized values for each environment.

## Prerequisites

- CloudNativePG operator must be installed first (see `apps/platform/cnpg-operator/`)
- Kubernetes cluster with appropriate storage class configured
- Helm 3.x installed
- kubectl configured to access the cluster
- Application secret created in target namespace

## Available Environments

| Environment | Values file | Argo CD Application | Helm release | Namespace | Instances | Storage |
|---|---|---|---|---|---|---|
| **local/dev** | `environments/local/dev.yaml` | `cnpg-cluster-local-dev` | `platform-postgres-dev` | `data-dev` | 1 | 20Gi + 1Gi WAL (longhorn) |

Es el único entorno que existe. Los values de `qa`, `prod` y `cloud/*` se borraron en la issue #44: nunca
llegaron a desplegar nada (ponían las claves en `cluster.instances` cuando el subchart espera
`cluster.cluster.instances`) y los namespaces `data-qa` / `data-prod` no existen en el clúster.

El otro cluster CNPG del homelab, `authentik-postgres-casa` (ns `data-casa`), vive en
`apps/data/authentik-postgres` — es un chart hermano, no un entorno de éste.

### Alta disponibilidad: por qué esto va a 1 instancia

La `nodeAffinity` de `environments/local/dev.yaml` exige `node-role.kubernetes.io/worker=true` **AND**
`node.kubernetes.io/performance=high`, y **`worker4` es el único worker que lleva esa etiqueta** (`worker3` es
`low`, el resto no la llevan; `master1` la lleva pero es control-plane, que es justo lo que la primera
expresión excluye). Con `instances: 2` el segundo pod se quedaría en `Pending`.

Para tener HA de verdad hay que hacer antes **una** de estas dos:

- etiquetar otro worker con `node.kubernetes.io/performance=high` desde `kxs-ansible` (el candidato natural es
  `worker6`: 8 GB, igual que `worker4`), o
- bajar la expresión de `performance` de `requiredDuringScheduling...` a `preferredDuringScheduling...`,
  dejando `worker` como la única condición dura.

Y cuando haya 2+ instancias, avisar en `k3s-local-apps-manifests` para añadir a `rules-cnpg.yaml` las alertas
de réplica caída y de replication lag, que hoy no existen porque con una instancia no hay nada que medir.

Mientras tanto, la recuperación de este cluster es **por backup, no por failover**.

## Bases de datos y roles

Este Postgres es **multi-inquilino**: lo comparten varias aplicaciones, cada una con su base y su role.
Lo que sigue es el inventario, y sobre todo qué parte de él está declarada.

| Base | Role dueño | Quién la usa | ¿Declarada? |
|---|---|---|---|
| `platform` | `platform` | — | sí, `cluster.cluster.initdb` |
| `deal_tracker` | `deal_tracker` | deal-tracker dev | **no** |
| `deal_tracker_qa` | `deal_tracker_qa` | deal-tracker qa | **no** |
| `keycloak_dev` | `postgres` | Keycloak (`security-dev`) | **no** |
| `tradingtool-dev` | `tradingtool-dev-user` | tradingtools dev | **no** |
| `tradingtool-qa` | `tradingtool-qa-user` | tradingtools qa | **no** |
| ~~`deal_tracker_prod`~~ | — | — | **se fue en la #71**, ver abajo |

Las cinco marcadas se crearon a mano contra el secret superusuario y **no aparecen en ningún repositorio**.
El backup físico devuelve los *datos*; el reparto de bases, dueños y roles no está escrito en ninguna
parte, así que reconstruir este cluster desde cero es hoy recrear cinco bases a mano y acordarse de quién
era dueño de cada una. Es el mismo agujero que los realms de Keycloak antes de la #49.

**Y desde la #71 vuelve a ser el agujero entero.** `deal_tracker_prod` —la base de producción de
deal-tracker— se trasladó al cluster general del tier de producción (`apps/data/platform-postgres`,
release `platform-postgres-prod`, ns `data-prod`), porque compartir pod de `instances: 1` con dev y QA
significaba que un rollout provocado por cualquiera de los otros inquilinos era una caída de producción.
Era **la única** base declarada además de la del initdb, así que este cluster se queda otra vez sin
ningún role en git y con cinco de sus seis bases sin escribir en ninguna parte.

Queda **una copia de `deal_tracker_prod` en este Postgres**, a propósito: `databaseReclaimPolicy: retain`
hace que quitar el CRD `Database` no dropee nada, y sacar el role de `managed.roles` sólo lo deja
`not-managed`. Es la red de seguridad del traslado. Borrarla —base, role y el Secret huérfano
`deal-tracker-prod-db`— es un paso a mano y deliberado, cuando haya confianza suficiente.

Desde CNPG 1.25 hay mecanismo nativo y no hace falta montar nada: el CRD `Database`
(`cluster.databases`) y `spec.managed.roles` (`cluster.cluster.roles`), los dos reconciliados por el
operador. La #53 estrenó el patrón con `deal_tracker_prod`, que era nueva y no podía romper nada — y
`apps/data/platform-postgres` es hoy el ejemplo vivo de las tres piezas juntas.

**Adoptar las cinco va de una en una, con verificación entre medias**, y por un motivo concreto: declarar
un role que ya existe con su `passwordSecret` hace que CNPG **le resetee la contraseña** a la del secret.
Si el valor sellado no es exactamente el que usa hoy la aplicación, se cae. En lote, se caen las cinco a la vez.

### Añadir una base nueva

Tres piezas en `environments/local/dev.yaml`, y las tres en el mismo commit:

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
  databases:                     # hermana de cluster.cluster, no dentro
    - name: mi_app
      owner: mi_app
      databaseReclaimPolicy: retain

roleSecrets:
  mi-app-db:
    username: "<ciphertext de: mi_app>"
    password: "<ciphertext>"
```

El `username` sellado tiene que ser **literalmente el nombre del role**. Y `retain` se escribe explícito
aunque sea el default del CRD: con `delete`, borrar el objeto `Database` DROPea la base.

El objeto `Database` se llamará `platform-postgres-dev-mi-app` (el prefijo lo impone el subchart); el
nombre que importa —el de la base— es `spec.name`.

## Secrets Management

Los tres Secret del chart se renderizan como `SealedSecret` desde `templates/`, con el ciphertext viviendo
directamente en el values de entorno. No hay ficheros de Secret sueltos: el antiguo
`environments/local/secrets/` se borró en la issue #44.

| Secret | Template | Bloque de values | Para qué |
|---|---|---|---|
| `platform-postgres-app` | `templates/sealedsecret.yaml` | `sealedSecret` | credenciales de la BD `platform` |
| `cnpg-backup-s3-creds` | `templates/backup-s3-sealedsecret.yaml` | `backupSecret` | credencial S3 del backup a MinIO |

`roleSecrets` está **vacío** desde la #71: su única entrada, `deal-tracker-prod-db`, se fue con el role.
El template sigue aquí porque quedan cinco roles por adoptar. Va por **mapa** (clave = nombre del Secret)
en vez de un bloque por secret como los otros dos, porque cinco roles serían cinco bloques casi iguales. Y su template
emite `type: kubernetes.io/basic-auth`, no `Opaque`: es lo que CNPG exige para un `passwordSecret`, y
además compara el `username` de dentro con el nombre del role. Si no cuadra, ignora la contraseña **sin
avisar** — el Secret se desella, el Cluster sincroniza, y el role se queda sin poder entrar.

Se sella valor a valor con `--raw`. El namespace y el nombre **forman parte del cifrado**: tienen que coincidir
exactamente con el destino, y la misma credencial en otro namespace hay que sellarla otra vez.

```bash
echo -n "your-value" | kubeseal --raw --from-file=/dev/stdin \
  --namespace data-dev --name platform-postgres-app \
  --controller-name sealed-secrets --controller-namespace kube-system
```

La salida se pega bajo `<bloque>.encryptedData.<campo>` en `environments/local/dev.yaml`. El ciphertext es
seguro de commitear; el controller `sealed-secrets` de `kube-system` lo desella en el clúster.

**Security Note:** Never commit plain secrets to Git.

## Deployment

### Using Helm CLI

First, update Helm dependencies:

```bash
cd apps/data/cnpg
helm dependency update
```

Deploy to a specific environment:

```bash
# Local dev environment (render only; el despliegue real va por Argo CD)
helm upgrade --install platform-postgres-dev . \
  --namespace data-dev \
  --create-namespace \
  --values values.yaml \
  --values environments/local/dev.yaml
```

### Using Argo CD (preferido)

La Application ya está en el repo: `argocd/clusters/local/dev.yaml`.

```bash
kubectl apply -f apps/data/cnpg/argocd/clusters/local/dev.yaml
argocd app sync cnpg-cluster-local-dev
```

Ojo con `releaseName: platform-postgres-dev`: es load-bearing. Si cambia, los recursos se recrean con otros
nombres y los viejos se podan.

## Verification

After deployment, verify the cluster is running:

```bash
# Check Helm release
helm list -n data-dev

# Check cluster status
kubectl get cluster -n data-dev
kubectl cnpg status platform-postgres -n data-dev

# Check pods
kubectl get pods -n data-dev

# Check services
kubectl get svc -n data-dev

# Expected services:
# - platform-postgres-rw (read-write primary)
# - platform-postgres-ro (read-only replicas)
# - platform-postgres-r  (read service)

# Check PVCs
kubectl get pvc -n data-dev
```

## Connecting to the Database

### From within the cluster

```bash
# Read-write connection (primary)
psql -h platform-postgres-rw.data-dev.svc.cluster.local -U platform -d platform

# Read-only connection (replicas)
psql -h platform-postgres-ro.data-dev.svc.cluster.local -U platform -d platform
```

### Port-forward for local access

```bash
kubectl port-forward -n data-dev svc/platform-postgres-rw 5432:5432

# Then connect locally
psql -h localhost -U platform -d platform
```

### Get credentials

```bash
# Application credentials
kubectl get secret platform-postgres-app -n data-dev -o jsonpath='{.data.password}' | base64 -d

# Superuser credentials (auto-generated by CNPG)
kubectl get secret platform-postgres-superuser -n data-dev -o jsonpath='{.data.password}' | base64 -d
```

## Configuration

**Todo lo del subchart cuelga de `cluster.cluster.*`, no de `cluster.*`.** El primer nivel es la clave del
subchart en el wrapper; el segundo es su propia sección `cluster`. Confundirlos es silencioso: Helm acepta el
values, el subchart lo ignora y el Cluster sale con los defaults. Es exactamente lo que les pasaba a los values
de `qa`/`prod` que se borraron en la issue #44.

### Storage Class

`longhorn`, en `environments/local/dev.yaml`:

```yaml
cluster:
  cluster:
    storage:
      storageClass: longhorn
      size: 20Gi
    walStorage:
      storageClass: longhorn
      size: 1Gi
```

### Resource Limits

```yaml
cluster:
  cluster:
    resources:
      requests:
        cpu: "250m"
        memory: "512Mi"
      limits:
        cpu: "1"
        memory: "2Gi"
```

### Instance Count

```yaml
cluster:
  cluster:
    instances: 1
```

Leer antes "Alta disponibilidad: por qué esto va a 1 instancia" más arriba — subirlo sin tocar la afinidad deja
el segundo pod en `Pending`.

### PostgreSQL Parameters

```yaml
cluster:
  cluster:
    postgresql:
      parameters:
        max_connections: "100"
        shared_buffers: "128MB"
```

## Backups

**Las 3 réplicas de Longhorn no son un backup.** Protegen de perder un disco; no de un `DROP TABLE` ni de una
corrupción lógica. Lo que cubre eso es el backup del operator (`barmanObjectStore` + `ScheduledBackup`), que es
lo que hay configurado aquí. `BACKUPS.md` de `k3s-local-apps-manifests` dice lo mismo.

### Cómo está montado

| Pieza | Dónde |
|---|---|
| Destino | MinIO de sv2, `http://192.168.50.240:9000`, bucket `cnpg-backup` |
| Ruta | `s3://cnpg-backup/<nombre-del-cluster>/` — CNPG separa por `serverName`, los dos clusters comparten bucket sin pisarse |
| Credencial | Secret `cnpg-backup-s3-creds` (claves `ACCESS_KEY_ID` / `ACCESS_SECRET_KEY`), sellado en `templates/backup-s3-sealedsecret.yaml` |
| Horario | `0 30 1 * * *` (01:30 UTC; formato CNPG de **6 campos**, el primero son segundos) |
| Retención | 30 días |
| Compresión / cifrado | gzip / ninguno — el MinIO no tiene SSE, y el `AES256` que trae el chart por defecto haría fallar cada PUT |

El bucket es distinto del `longhorn-backup` a propósito: credencial separada, rotación independiente y radio
de daño acotado.

### Alta y rotación de la credencial

**El bucket, la policy y el usuario NO se crean aquí ni a mano**: los gestiona `kxs-ansible`
(`roles/minio_creds` + `playbooks/minio_creds.yml`, [#47](https://github.com/juanjocop/kxs-ansible/pull/47)),
que es el repo dueño del host `docker-sv2`. El plaintext vive en su vault cifrado
(`vault_minio_cnpg_backup_secret_key`). Se hizo así por la lección de `longhorn-backup`: se creó a mano y fuera
de Git, y cuando dejó de valer nadie sabía cuál era la buena — 49 días de backups caídos
([k3s-local-apps-manifests#7](https://github.com/juanjocop/k3s-local-apps-manifests/issues/7)).

La playbook también sella, en su paso `--tags seal`, y deja los 4 ciphertexts en
`out/cnpg-backup-s3-creds.yaml`. Lo único que se hace en este repo es pegarlos. El sellado equivalente a mano,
si hiciera falta — un SealedSecret va atado a namespace + nombre, así que la misma credencial se sella **dos
veces**, una por namespace:

```bash
echo -n "<access-key>" | kubeseal --raw --from-file=/dev/stdin \
  --namespace data-dev --name cnpg-backup-s3-creds \
  --controller-name sealed-secrets --controller-namespace kube-system
echo -n "<secret-key>" | kubeseal --raw --from-file=/dev/stdin \
  --namespace data-dev --name cnpg-backup-s3-creds \
  --controller-name sealed-secrets --controller-namespace kube-system
```

La salida va a `backupSecret.encryptedData.{accessKeyId,secretAccessKey}` de
`environments/local/dev.yaml`, y la del namespace `data-casa` a `apps/data/authentik-postgres`.

`cluster.backups.enabled` y `backupSecret.enabled` se encienden **a la vez y en el mismo commit que el
ciphertext**: con el primero a true y sin el Secret, el archivado de WAL falla y el Cluster se queda con la
condición `ContinuousArchiving` en `False`.

Para **rotar**: clave nueva en el vault, re-ejecutar la playbook (detecta que la del vault ya no coincide con
MinIO y la reescribe) y re-pegar los ciphertexts en los dos ficheros. Mientras ese commit no esté sincronizado
los backups fallan con `SignatureDoesNotMatch`, así que conviene hacerlo fuera del horario de los backups
programados. Procedimiento completo en `kxs-ansible/docs/MINIO_CREDS.md`.

Un detalle de la playbook que confunde: con el sellado incluido siempre sale `changed=1`. **kubeseal no es
determinista** (cada sellado usa una clave de sesión aleatoria), así que el fichero de `out/` se reescribe
aunque el plaintext sea el mismo. Eso no es drift y no hay que re-pegar nada.

### Comprobar que funciona

**`ContinuousArchiving: True` NO es prueba de nada.** CNPG arranca con `archive_mode=on` siempre, y esa
condición ya estaba en `True` en los dos clusters *meses antes* de que existiera ningún destino configurado
(`lastTransitionTime` de febrero y junio de 2026, con los backups encendidos el 29-07). No distingue "archivo
bien" de "no tengo dónde archivar". No la uses como criterio de éxito.

Lo que sí lo prueba, en orden:

```bash
# 1. El Secret se ha desellado (si falta, todo lo demás falla)
kubectl -n data-dev get secret cnpg-backup-s3-creds

# 2. El Backup ha terminado, y sin error
kubectl -n data-dev get backups.postgresql.cnpg.io \
  -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,ERROR:.status.error'
#    OJO: `kubectl get backup` a secas resuelve a backup.longhorn.io, no a CNPG.

# 3. El operator reconoce un punto de restauración — este campo es de fiar
kubectl -n data-dev get cluster platform-postgres-dev \
  -o jsonpath='{.status.firstRecoverabilityPoint}{"  ultimo: "}{.status.lastSuccessfulBackup}{"\n"}'

# 4. La prueba final: que barman vea el backup en el bucket
AK=$(kubectl -n data-dev get secret cnpg-backup-s3-creds -o jsonpath='{.data.ACCESS_KEY_ID}' | base64 -d)
SK=$(kubectl -n data-dev get secret cnpg-backup-s3-creds -o jsonpath='{.data.ACCESS_SECRET_KEY}' | base64 -d)
kubectl -n data-dev exec platform-postgres-dev-1 -c postgres -- \
  env AWS_ACCESS_KEY_ID="$AK" AWS_SECRET_ACCESS_KEY="$SK" AWS_REGION=us-east-1 \
  barman-cloud-backup-list --endpoint-url http://192.168.50.240:9000 s3://cnpg-backup platform-postgres-dev
```

El `ScheduledBackup` se crea con `immediate: true`, así que el primer backup arranca al sincronizar, sin
esperar al cron.

### Restaurar

Se restaura a un **cluster nuevo**, no sobre el existente: se pone `mode: recovery` en el wrapper (ver
`recovery.*` en los values del subchart `cluster`) apuntando al mismo `destinationPath` y al `serverName` del
cluster origen, y se promueve cuando esté listo. Detalle en la
[documentación de recovery de CNPG](https://cloudnative-pg.io/documentation/current/recovery/).

### Caducidad conocida

El `barmanObjectStore` in-tree está **deprecado desde CNPG 1.26 y desaparece en 1.31** (el operator va por
1.28.1). Antes de esa versión hay que migrar al plugin `barman-cloud` (CNPG-I): subir el subchart `cluster`
0.6.1 → 0.8.x, desplegar el plugin en `cnpg-system` y traducir este bloque a un CR `ObjectStore`. Va en issue
aparte.

## Monitoring

**El PodMonitor no es de este repo.** Lo declara `k3s-local-apps-manifests` en
`prometheus/cnpg/podmonitor.yaml` (ns `monitoring`, con `namespaceSelector` sobre `data-dev` y `data-casa`) y
está verificado en vivo. Por eso `cluster.monitoring.podMonitor.enabled` va a `false` aquí: encenderlo crearía
un segundo PodMonitor y duplicaría el scrape. Si algún día queremos ser dueños del objeto, primero se borra el
del otro repo y luego se enciende esto — en ese orden.

`cluster.monitoring.prometheusRule.enabled` también va a `false`, y no es una cuestión de duplicado: las reglas
que genera el chart no llevan la etiqueta `prometheus: prometheus-persistant`, así que el `ruleSelector` de
nuestro Prometheus las ignoraría **en silencio**. Las reglas están escritas a medida en
`prometheus/prometheus/rules-cnpg.yaml`.

El exporter sirve métricas de todas formas: `.spec.monitoring` del Cluster no depende de esos flags, y el 9187
devuelve ~518 series `cnpg_`.

- `http://platform-postgres-dev-rw:9187/metrics` (primary)
- `http://platform-postgres-dev-ro:9187/metrics` (réplicas, cuando las haya)

## Upgrading

### Upgrade PostgreSQL Version

Update the image in `values.yaml`:

```yaml
cluster:
  imageName: ghcr.io/cloudnative-pg/postgresql:16.5
```

Then upgrade the release:

```bash
helm upgrade platform-postgres-dev . \
  --namespace data-dev \
  --values values.yaml \
  --values values-local-dev.yaml
```

### Upgrade Helm Chart

Update dependencies and upgrade:

```bash
helm dependency update
helm upgrade platform-postgres-dev . --namespace data-dev
```

## Troubleshooting

### Cluster not starting

Check operator logs:
```bash
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg
```

Check cluster events:
```bash
kubectl describe cluster platform-postgres -n data-dev
```

### Connection issues

Verify services exist:
```bash
kubectl get svc -n data-dev | grep platform-postgres
```

Check pod status:
```bash
kubectl get pods -n data-dev
kubectl logs -n data-dev platform-postgres-1
```

### Storage issues

Check PVC status:
```bash
kubectl get pvc -n data-dev
kubectl describe pvc -n data-dev
```

Verify storage class exists:
```bash
kubectl get storageclass
```

## Migration History

This chart uses Helm for deployment and configuration management. All settings are configured through values files in `environments/{local|cloud}/{env}.yaml`.

For historical context on the migration to Helm, see `docs/migration/` in the repository root.

## References

- [CloudNativePG Documentation](https://cloudnative-pg.io/)
- [CloudNativePG Cluster Chart](https://github.com/cloudnative-pg/charts/tree/main/charts/cluster)
- [PostgreSQL Configuration](https://www.postgresql.org/docs/current/runtime-config.html)
- [CNPG Backup & Recovery](https://cloudnative-pg.io/documentation/current/backup_recovery/)
