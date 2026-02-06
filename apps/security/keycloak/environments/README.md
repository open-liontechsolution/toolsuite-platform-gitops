# Keycloak Environment Configurations

This directory contains environment-specific value overlays for Keycloak deployments.

## Structure

```
environments/
├── local/
│   ├── dev.yaml      # Local development environment
│   ├── qa.yaml       # Local QA environment
│   └── prod.yaml     # Local production environment
└── cloud/            # Future: Cloud provider environments
```

## Environment Overview

### Local Environments (k3s + Longhorn)

| Environment | Namespace     | Replicas | CPU Request | Memory Request | Database                    |
|-------------|---------------|----------|-------------|----------------|-----------------------------|
| **dev**     | security-dev  | 1        | 250m        | 512Mi          | keycloak_dev @ data-dev     |
| **qa**      | security-qa   | 2        | 500m        | 1Gi            | keycloak_qa @ data-qa       |
| **prod**    | security-prod | 2        | 1           | 2Gi            | keycloak_prod @ data-prod   |

## Configuration Requirements

### 1. Database Setup

Before deploying Keycloak, create the database and user in the corresponding CNPG PostgreSQL cluster:

```bash
# Connect to the PostgreSQL cluster
kubectl exec -it -n data-dev platform-postgres-dev-1 -- psql -U postgres

# Create database and user
CREATE DATABASE keycloak_dev;
CREATE USER keycloak_dev WITH ENCRYPTED PASSWORD 'your-secure-password';
GRANT ALL PRIVILEGES ON DATABASE keycloak_dev TO keycloak_dev;
\q
```

Repeat for QA and prod environments with appropriate names.

### 2. Sealed Secrets

Each environment requires two SealedSecrets:

#### Database Credentials

```bash
# Create plain secret (DO NOT COMMIT)
cat > /tmp/db-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-db-credentials
  namespace: security-dev
type: Opaque
stringData:
  db-user: keycloak_dev
  db-password: your-secure-password
EOF

# Encrypt with kubeseal
kubeseal --format=yaml \
  --namespace security-dev \
  < /tmp/db-secret.yaml \
  > /tmp/db-sealed.yaml

# Extract encrypted values
cat /tmp/db-sealed.yaml
```

#### Admin Credentials

```bash
# Create plain secret (DO NOT COMMIT)
cat > /tmp/admin-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-admin-credentials
  namespace: security-dev
type: Opaque
stringData:
  admin-password: your-admin-password
EOF

# Encrypt with kubeseal
kubeseal --format=yaml \
  --namespace security-dev \
  < /tmp/admin-secret.yaml \
  > /tmp/admin-sealed.yaml

# Extract encrypted values
cat /tmp/admin-sealed.yaml
```

#### Update Environment Files

Copy the `encryptedData` values from the sealed secrets and update the environment YAML files:

```yaml
sealedSecret:
  enabled: true
  dbCredentials:
    name: keycloak-db-credentials
    encryptedData:
      db-user: "AgBRsEWrHhffQq0slDQmsJvGs8b..."  # From sealed secret
      db-password: "AgAyrgE9rX1hPF5IgMz9tQ0PZ..."  # From sealed secret
  adminCredentials:
    name: keycloak-admin-credentials
    encryptedData:
      admin-password: "AgBXYZ123..."  # From sealed secret
```

### 3. NetworkPolicy

NetworkPolicy is automatically enabled in each environment to allow:
- Egress to PostgreSQL in `data-{env}` namespace (port 5432)
- DNS resolution to kube-system (port 53)
- HTTP/HTTPS for Keycloak operations

No manual configuration required.

## Deployment

See the main [README.md](../README.md) for deployment instructions.

## Security Notes

- **Never commit plaintext secrets** to Git
- Use namespace-scoped sealed secrets for better security
- Delete temporary secret files after encryption
- Rotate passwords regularly
- Use strong passwords (minimum 16 characters)
