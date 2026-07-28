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

## Secrets Management

Los dos Secret del chart se renderizan como `SealedSecret` desde `templates/`, con el ciphertext viviendo
directamente en el values de entorno. No hay ficheros de Secret sueltos: el antiguo
`environments/local/secrets/` se borró en la issue #44.

| Secret | Template | Bloque de values | Para qué |
|---|---|---|---|
| `platform-postgres-app` | `templates/sealedsecret.yaml` | `sealedSecret` | credenciales de la BD `platform` |
| `cnpg-backup-s3-creds` | `templates/backup-s3-sealedsecret.yaml` | `backupSecret` | credencial S3 del backup a MinIO |

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
| Destino | MinIO de sv2, `http://192.168.50.100:9000`, bucket `cnpg-backup` |
| Ruta | `s3://cnpg-backup/<nombre-del-cluster>/` — CNPG separa por `serverName`, los dos clusters comparten bucket sin pisarse |
| Credencial | Secret `cnpg-backup-s3-creds` (claves `ACCESS_KEY_ID` / `ACCESS_SECRET_KEY`), sellado en `templates/backup-s3-sealedsecret.yaml` |
| Horario | `0 30 1 * * *` (01:30 UTC; formato CNPG de **6 campos**, el primero son segundos) |
| Retención | 30 días |
| Compresión / cifrado | gzip / ninguno — el MinIO no tiene SSE, y el `AES256` que trae el chart por defecto haría fallar cada PUT |

El bucket es distinto del `longhorn-backup` a propósito: credencial separada, rotación independiente y radio
de daño acotado.

### Alta y rotación de la credencial

El bucket y el usuario se crean **a mano en MinIO** (no hay GitOps de MinIO). Después, sellar la credencial una
vez por namespace — un SealedSecret va atado a namespace + nombre:

```bash
echo -n "<access-key>" | kubeseal --raw --from-file=/dev/stdin \
  --namespace data-dev --name cnpg-backup-s3-creds \
  --controller-name sealed-secrets --controller-namespace kube-system
echo -n "<secret-key>" | kubeseal --raw --from-file=/dev/stdin \
  --namespace data-dev --name cnpg-backup-s3-creds \
  --controller-name sealed-secrets --controller-namespace kube-system
```

La salida va a `backupSecret.encryptedData.{accessKeyId,secretAccessKey}` de
`environments/local/dev.yaml`. La **misma** credencial hay que sellarla otra vez contra `data-casa` para
`apps/data/authentik-postgres`.

`cluster.backups.enabled` y `backupSecret.enabled` se encienden **a la vez**: con el primero a true y sin el
Secret, el archivado de WAL falla y el Cluster se queda con la condición `ContinuousArchiving` en `False`.

### Comprobar que funciona

```bash
kubectl -n data-dev get secret cnpg-backup-s3-creds     # lo desella el controller
kubectl -n data-dev get scheduledbackup
kubectl -n data-dev get backup -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,ERROR:.status.error'
kubectl -n data-dev get cluster platform-postgres-dev \
  -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")]}'
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
