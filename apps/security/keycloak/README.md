# Keycloak Identity and Access Management (Helm Chart)

This component deploys Keycloak using the Bitnami Helm chart with external PostgreSQL (CloudNativePG) and Sealed Secrets for credential management. Each environment (dev/qa/prod) can be deployed independently with environment-specific configurations.

## Overview

Keycloak is a high-performance Java-based identity and access management solution that provides authentication, authorization, and single sign-on (SSO) capabilities. This deployment uses:

- **Bitnami Keycloak Helm Chart** (v25.3.0, Keycloak 26.3.3)
- **External PostgreSQL** via CloudNativePG clusters
- **Sealed Secrets** for secure credential management
- **NetworkPolicy** for cross-namespace database access
- **GitOps** deployment via ArgoCD

## Prerequisites

- CloudNativePG PostgreSQL clusters deployed (see `apps/data/cnpg/`)
- Sealed Secrets controller installed
- Kubernetes cluster with Longhorn storage (local) or cloud storage
- Helm 3.8.0+
- kubectl configured to access the cluster
- kubeseal CLI for encrypting secrets

## Available Environments

### Local Environments (k3s + Longhorn)

| Environment | Namespace     | Replicas | CPU Request | Memory Request | Database                    |
|-------------|---------------|----------|-------------|----------------|-----------------------------|
| **dev**     | security-dev  | 1        | 250m        | 512Mi          | keycloak_dev @ data-dev     |

**dev es el unico entorno que existe.** Hubo values y Applications de `qa` y `prod` desde el commit
inicial, nunca desplegados y que no habrian funcionado: anidaban bajo `keycloak:` cuando el subchart
es `keycloakx`, apuntaban a `data-prod`/`data-qa` (namespaces que no existen) y llevaban
`REPLACE_WITH_ENCRYPTED_*` en los secretos. Se borraron; escribirlos de nuevo cuando hagan falta
cuesta menos que confiar en ellos.

El prod de deal-tracker no necesita una instancia nueva: estrena **realm** propio en esta, declarado
en `realms/`. Ver la issue #50.

## Database Setup

Before deploying Keycloak, create the database and user in the corresponding CNPG PostgreSQL cluster.

### Create Database for Dev Environment

```bash
# Port-forward to PostgreSQL
kubectl port-forward -n data-dev svc/platform-postgres-dev-rw 5432:5432

# In another terminal, connect to PostgreSQL
psql -h localhost -U postgres -d postgres

# Create database and user
CREATE DATABASE keycloak_dev;
CREATE USER keycloak_dev WITH ENCRYPTED PASSWORD 'your-secure-password';
GRANT ALL PRIVILEGES ON DATABASE keycloak_dev TO keycloak_dev;

# Grant schema permissions
\c keycloak_dev
GRANT ALL ON SCHEMA public TO keycloak_dev;
\q
```

Repeat for QA and prod environments with appropriate names (`keycloak_qa`, `keycloak_prod`).

## Secrets Management

Keycloak requires two secrets per environment:
1. **Database credentials** (username and password)
2. **Admin credentials** (admin password)

### Generate Sealed Secrets

#### 1. Database Credentials

```bash
# Create temporary plain secret file
cat > /tmp/keycloak-db-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-db-credentials
  namespace: security-dev
type: Opaque
stringData:
  db-user: keycloak_dev
  db-password: your-secure-db-password
EOF

# Encrypt with kubeseal
kubeseal --format=yaml \
  --namespace security-dev \
  < /tmp/keycloak-db-secret.yaml \
  > /tmp/keycloak-db-sealed.yaml

# View the sealed secret
cat /tmp/keycloak-db-sealed.yaml
```

#### 2. Admin Credentials

```bash
# Create temporary plain secret file
cat > /tmp/keycloak-admin-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-admin-credentials
  namespace: security-dev
type: Opaque
stringData:
  admin-password: your-secure-admin-password
EOF

# Encrypt with kubeseal
kubeseal --format=yaml \
  --namespace security-dev \
  < /tmp/keycloak-admin-secret.yaml \
  > /tmp/keycloak-admin-sealed.yaml

# View the sealed secret
cat /tmp/keycloak-admin-sealed.yaml
```

#### 3. Update Environment Values

Copy the `encryptedData` values from the sealed secrets and update the corresponding environment file:

Edit `environments/local/dev.yaml`:

```yaml
sealedSecret:
  enabled: true
  dbCredentials:
    name: keycloak-db-credentials
    encryptedData:
      db-user: "AgBRsEWrHhffQq0slDQmsJvGs8b..."  # Paste encrypted value
      db-password: "AgAyrgE9rX1hPF5IgMz9tQ0PZ..."  # Paste encrypted value
  adminCredentials:
    name: keycloak-admin-credentials
    encryptedData:
      admin-password: "AgBXYZ123..."  # Paste encrypted value
```

#### 4. Clean Up

```bash
# Delete temporary files
rm /tmp/keycloak-*-secret.yaml /tmp/keycloak-*-sealed.yaml
```

**Important**: Never commit plaintext secrets to Git!

## Deployment

### Using Helm CLI

First, update Helm dependencies:

```bash
cd apps/security/keycloak
helm dependency update
```

Deploy to a specific environment:

```bash
# Local dev environment
helm upgrade --install keycloak-dev . \
  --namespace security-dev \
  --create-namespace \
  --values values.yaml \
  --values environments/local/dev.yaml
```

### Using Argo CD

Apply the ArgoCD Application manifest:

```bash
# Deploy dev environment
kubectl apply -f argocd/clusters/local/dev.yaml

# Deploy QA environment
kubectl apply -f argocd/clusters/local/qa.yaml

# Deploy prod environment
kubectl apply -f argocd/clusters/local/prod.yaml
```

Monitor the deployment:

```bash
# Watch ArgoCD sync
argocd app get keycloak-local-dev

# Watch pods
kubectl get pods -n security-dev -w
```

## Verification

After deployment, verify Keycloak is running:

```bash
# Check Helm release
helm list -n security-dev

# Check pods
kubectl get pods -n security-dev

# Check services
kubectl get svc -n security-dev

# Check NetworkPolicy
kubectl get networkpolicy -n security-dev

# Check sealed secrets were unsealed
kubectl get secrets -n security-dev | grep keycloak
```

Expected pods:
- `keycloak-dev-0` (StatefulSet pod)

Expected services:
- `keycloak-dev` (ClusterIP)
- `keycloak-dev-headless` (Headless service)

## Accessing Keycloak

### Port-Forward for Local Access

```bash
# Forward to Keycloak service
kubectl port-forward -n security-dev svc/keycloak-dev 8080:80

# Access Keycloak
# URL: http://localhost:8080
# Admin Console: http://localhost:8080/admin
```

### Retrieve Admin Credentials

```bash
# Get admin username (default: admin)
echo "admin"

# Get admin password
kubectl get secret keycloak-admin-credentials -n security-dev \
  -o jsonpath='{.data.admin-password}' | base64 -d
echo
```

### First Login

1. Open browser to `http://localhost:8080/admin`
2. Login with username `admin` and the password from above
3. You'll be redirected to the Keycloak Admin Console

## Configuration

### Database Connection

Database connection is configured via environment overlays. The connection uses:

- **Host**: `platform-postgres-{env}-rw.data-{env}.svc.cluster.local`
- **Port**: `5432`
- **Database**: `keycloak_{env}`
- **Credentials**: From `keycloak-db-credentials` secret

### NetworkPolicy

NetworkPolicy is automatically created to allow:

- **Egress to PostgreSQL**: Port 5432 to `data-{env}` namespace
- **DNS Resolution**: Port 53 to `kube-system` namespace
- **HTTP/HTTPS**: Ports 80/443 for Keycloak operations

Verify NetworkPolicy:

```bash
kubectl get networkpolicy -n security-dev
kubectl describe networkpolicy keycloak-dev-egress -n security-dev
```

### Resource Limits

Adjust resources in environment-specific values files:

```yaml
keycloak:
  resources:
    requests:
      cpu: "1"
      memory: "2Gi"
    limits:
      cpu: "4"
      memory: "8Gi"
```

### Replica Count

Change the number of Keycloak instances:

```yaml
keycloak:
  replicaCount: 2  # 1 for dev, 2+ for HA
```

## Testing Database Connectivity

Test database connection from Keycloak pod:

```bash
# Get pod name
POD=$(kubectl get pod -n security-dev -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}')

# Test DNS resolution
kubectl exec -n security-dev $POD -- nslookup platform-postgres-dev-rw.data-dev.svc.cluster.local

# Test PostgreSQL connection (if psql is available)
kubectl exec -n security-dev $POD -- bash -c \
  "apt-get update && apt-get install -y postgresql-client && \
   PGPASSWORD=\$(cat /opt/bitnami/keycloak/secrets/db-password) \
   psql -h platform-postgres-dev-rw.data-dev.svc.cluster.local \
   -U \$(cat /opt/bitnami/keycloak/secrets/db-user) \
   -d keycloak_dev -c 'SELECT version();'"
```

## Troubleshooting

### Pod Not Starting

Check pod logs:

```bash
kubectl logs -n security-dev -l app.kubernetes.io/name=keycloak
```

Common issues:
- Database connection failed: Check NetworkPolicy and database credentials
- Secret not found: Verify SealedSecrets were created and unsealed
- Image pull errors: Check image availability
  - Override the image tag in `values.yaml` if Bitnami removes a revision (for example, update `keycloak.image.tag` to the latest `*-debian-12-rN` tag).

### Database Connection Issues

```bash
# Check if secret exists and is unsealed
kubectl get secret keycloak-db-credentials -n security-dev

# Check NetworkPolicy
kubectl describe networkpolicy -n security-dev

# Check if PostgreSQL is accessible
kubectl get svc -n data-dev | grep postgres
```

### Sealed Secret Not Unsealing

```bash
# Check sealed-secrets controller
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets

# Verify secret was created in correct namespace
kubectl get sealedsecrets -n security-dev

# Check events
kubectl get events -n security-dev --sort-by='.lastTimestamp'
```

### NetworkPolicy Blocking Traffic

```bash
# Temporarily disable NetworkPolicy for testing
kubectl delete networkpolicy keycloak-dev-egress -n security-dev

# Test connectivity
# ... perform tests ...

# Re-apply NetworkPolicy
kubectl apply -f <(helm template . --values values.yaml --values environments/local/dev.yaml | grep -A 50 "kind: NetworkPolicy")
```

## Upgrading

### Upgrade Keycloak Version

Update the Bitnami chart version in `Chart.yaml`:

```yaml
dependencies:
  - name: keycloak
    version: "25.4.0"  # New version
    repository: https://charts.bitnami.com/bitnami
```

Then upgrade:

```bash
helm dependency update
helm upgrade keycloak-dev . \
  --namespace security-dev \
  --values values.yaml \
  --values environments/local/dev.yaml
```

### Upgrade Helm Chart

```bash
cd apps/security/keycloak
helm dependency update
helm upgrade keycloak-dev . --namespace security-dev
```

## Realms declarados en git

Los realms y sus clients se declaran en `realms/*.yaml` y los aplica
[keycloak-config-cli](https://github.com/adorsys/keycloak-config-cli). Antes vivian solo en la
Postgres de Keycloak, asi que un cambio hecho a mano no dejaba rastro en ningun diff — que es como
un `webOrigins` mal puesto tumbo el login de QA de deal-tracker durante una release entera
(`deal-tracker#219`, issue #49 de este repo).

Esta instancia hospeda varios realms. **config-cli solo entra en los que aparecen en `realms/`**;
el resto no se toca.

| Realm | Fichero | Consumidor |
|---|---|---|
| `deal-tracker-dev` | `realms/deal-tracker-dev.yaml` | el entorno **QA** de deal-tracker (el nombre engana: no hay ninguna redirect URI de dev) |
| `deal-tracker-prod` | `realms/deal-tracker-prod.yaml` | produccion de deal-tracker, `dealtracker.liontechsolution.com` |
| `tradingtool-dev`, `tradingtool-qa` | — | sin declarar todavia; config-cli no los toca |

Los dos realms de deal-tracker estan separados a proposito: compartir client es lo que convirtio un
`webOrigins` mal puesto en una caida de login para todo QA, y con prod dentro habria sido una caida
de produccion. El `KEYCLOAK_ISSUER_URL` y el `KEYCLOAK_AUDIENCE` de cada entorno viven en
`deal-tracker/overlays/*/secret.example.yaml` del repo de manifiestos: **el nombre del realm y el del
client son contrato entre repos**, cambiarlos aqui deja de validar los tokens alli.

### Como se ejecuta

| | Cuando | Para que |
|---|---|---|
| `Job` (hook `PostSync`) | En cada sync de la Application | El cambio intencionado |
| `CronJob` | A diario, 04:00 Europe/Madrid | Revertir cambios hechos a mano |

La Application `keycloak-local-dev` es de sync manual (sin `automated`), asi que el CronJob es lo
que hace que la reconciliacion no dependa de que alguien sincronice.

**Consecuencia: un arreglo con `kcadm.sh` dura como mucho hasta la siguiente pasada.** A partir de
aqui, un `webOrigins` roto se arregla en un PR, no en el pod.

### Que se toca y que no

- **Las personas no se tocan nunca.** keycloak-config-cli no sabe borrarlas: `UserImportService`
  registra `"Purging users isn't supported in keycloak-config-cli!"` incluso si se le pasa
  `users: []`. El auto-registro de usuarios es seguro frente al CronJob.
  La **unica** entrada `users:` de `realms/` es el service account de `deal-tracker-api` (issue
  #61) — no es una persona, no tiene contrasena y se retira borrando su client, y config-cli no
  sabe asignarle su rol de ninguna otra forma. Ahi solo van service accounts; el razonamiento
  entero esta en [`docs/KEYCLOAK_USERS.md`](../../../docs/KEYCLOAK_USERS.md).
- **Lo no declarado se queda como esta**, con `import.managed.*=no-delete` (ver `values.yaml`).
  Comprobado sobre un realm de prueba: un ajuste de realm que el fichero no menciona sobrevive a la
  reconciliacion.
- **`import.cache.enabled=false` es deliberado.** Por defecto config-cli cachea un checksum del
  fichero y se salta la aplicacion si no cambio; como el fichero solo cambia en un commit, eso
  dejaria al CronJob sin efecto ninguno frente a un cambio hecho a mano.

### Anadir o cambiar un realm

1. Editar o crear el fichero en `realms/`.
2. Renderizar: `helm template keycloak-dev . -f values.yaml -f environments/local/dev.yaml`.
   El template **rechaza en tiempo de render** cualquier `webOrigins` con ruta o con `/*`: Keycloak
   compara la cabecera `Origin`, que nunca lleva ruta, y con `/*` no casa nunca.
3. PR, merge, y `argocd app sync keycloak-local-dev`.

Los secretos no van aqui en claro. Los clients de navegador (`deal-tracker-web`) son publicos con
PKCE y no tienen secreto que guardar. El confidencial, `deal-tracker-api`, **si tiene uno y tampoco
se declara**: lo genera Keycloak al crear el client y config-cli no lo toca nunca —con `secret`
ausente, su `ClientImportService.isClientEqual` devuelve `true` sin llegar a consultarlo, asi que la
reconciliacion nocturna no lo rota. Se saca una vez y se sella en el repo de manifiestos:

```bash
./scripts/keycloak-client-secret.sh deal-tracker-dev deal-tracker-api \
  | kubeseal --raw --from-file=/dev/stdin --namespace deal-tracker-qa --name deal-tracker-config \
    --controller-name sealed-secrets --controller-namespace kube-system
```

### Alta de usuarios

Las personas **no** se declaran en `realms/` —ver arriba por que— asi que el alta es su propio
procedimiento: `scripts/keycloak-user.sh`, con `crear`, `listar`, `reset`, `baja` y `alta`.

```bash
./scripts/keycloak-user.sh crear deal-tracker-prod ana ana@example.com Ana Perez
```

Reparte una contrasena **temporal** y fuerza `UPDATE_PASSWORD` en el primer login. Que el alta sea
manual no es un pendiente: es que las personas no pueden declararse en git —config-cli no sabe
borrarlas y el CronJob de las 04:00 desharia cada baja—, y eso no cambia con nada de lo de abajo.
La politica y las trampas del script estan en
[`docs/KEYCLOAK_USERS.md`](../../../docs/KEYCLOAK_USERS.md).

### Correo saliente y politica de contrasena

Los dos realms de deal-tracker tienen `smtpServer` contra **Resend** (issue #60), y con el
`resetPasswordAllowed`, `verifyEmail` y una `passwordPolicy`. Tres cosas que conviene saber antes
de tocarlo:

1. **La contrasena del SMTP no esta en `realms/`.** Entra por var-substitution:
   `password: $(env:SMTP_PASSWORD_DEAL_TRACKER_DEV)`, y la variable viene del SealedSecret
   `keycloak-realm-smtp`. Lo enciende `realmConfig.varSubstitution.enabled`; el prefijo es `$(`,
   no `${`, para no chocar con las variables propias de Keycloak.
   **Una variable que falte aborta el import de los DOS realms**, no solo del suyo
   (`import.var-substitution.undefined-is-error` viene `true` de fabrica). Es el comportamiento
   que se quiere: mejor eso que un realm con `$(env:...)` de contrasena.
2. **Una clave por realm, no una.** Cada uno manda desde su propio dominio verificado
   (`dealtracker-qa.…` y `dealtracker.…`): la de QA no puede servir para mandar como produccion.
3. **El 587 lo abre la NetworkPolicy, y es la unica regla que sale de verdad a internet.** Las
   demas van por `namespaceSelector`, que solo casa pods del cluster; esta lleva `ipBlock`. Sin
   ella Keycloak no manda un correo y el sintoma se lee como «no llega», no como «lo corta la
   policy». Se gobierna en `networkPolicy.smtp`.

La `passwordPolicy` es `length(12) and notUsername and notEmail and passwordHistory(3)`: longitud
sin reglas de composicion, siguiendo NIST 800-63B. **Es el unico sitio donde esa politica puede
vivir**, porque el alta por invitacion fija la contrasena por la Admin API y no por un formulario
de Keycloak.

## Monitoring and Metrics

Keycloak exposes metrics for Prometheus:

```yaml
keycloak:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
```

Metrics endpoint: `http://keycloak-dev:8080/metrics`

## Security Best Practices

- ✅ Use Sealed Secrets for all credentials
- ✅ Enable NetworkPolicy for network isolation
- ✅ Use external PostgreSQL (no embedded database)
- ✅ Enable production mode
- ✅ Use strong passwords (minimum 16 characters)
- ✅ Rotate credentials regularly
- ⏳ Configure TLS/HTTPS (via ingress, future)
- ⏳ Enable audit logging (future)
- ⏳ Implement backup strategy (future)

## References

- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [Bitnami Keycloak Chart](https://github.com/bitnami/charts/tree/main/bitnami/keycloak)
- [CloudNativePG Documentation](https://cloudnative-pg.io/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- [Kubernetes NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review Keycloak logs: `kubectl logs -n security-dev -l app.kubernetes.io/name=keycloak`
3. Check ArgoCD sync status: `argocd app get keycloak-local-dev`
4. Contact the Platform Team
