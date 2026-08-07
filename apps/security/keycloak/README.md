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
| **qa**      | security-qa   | 2        | 500m        | 1Gi            | keycloak_qa @ data-qa       |
| **prod**    | security-prod | 2        | 1           | 2Gi            | keycloak_prod @ data-prod   |

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

# Local QA environment
helm upgrade --install keycloak-qa . \
  --namespace security-qa \
  --create-namespace \
  --values values.yaml \
  --values environments/local/qa.yaml

# Local prod environment
helm upgrade --install keycloak-prod . \
  --namespace security-prod \
  --create-namespace \
  --values values.yaml \
  --values environments/local/prod.yaml
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

Esta instancia hospeda varios realms (`deal-tracker-dev`, `tradingtool-dev`, `tradingtool-qa`).
**config-cli solo entra en los realms que aparecen en `realms/`**; el resto no se toca.

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

- **Los usuarios no se tocan nunca.** keycloak-config-cli no sabe borrarlos: `UserImportService`
  registra `"Purging users isn't supported in keycloak-config-cli!"` incluso si se le pasa
  `users: []`. Y los ficheros de `realms/` no declaran usuarios, asi que el importador ni entra.
  El auto-registro de usuarios es seguro frente al CronJob.
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

Los secretos no van aqui en claro: el chart ya usa sealed-secrets, y los clients declarados son
publicos (PKCE), sin secreto que guardar.

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
