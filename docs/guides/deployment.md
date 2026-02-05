# Deployment Guide

Complete guide for deploying CloudNativePG PostgreSQL clusters using Helm and Argo CD.

## Prerequisites

### Required Tools

- **kubectl** - Kubernetes CLI
- **helm** (v3+) - Helm package manager
- **kubeseal** - Sealed Secrets CLI (for encrypting secrets)
- **argocd** CLI (optional) - For Argo CD management

### Required Components

Before deploying PostgreSQL clusters, ensure these are installed:

1. **Kubernetes Cluster** - k3s, EKS, GKE, AKS, etc.
2. **Argo CD** - GitOps deployment tool
3. **Sealed Secrets Controller** - For secret management
4. **Storage Class** - `longhorn` (local) or cloud storage class

### Verify Prerequisites

```bash
# Check kubectl access
kubectl cluster-info

# Check Argo CD
kubectl get pods -n argocd

# Check Sealed Secrets controller
kubectl get pods -n kube-system | grep sealed-secrets

# Check storage classes
kubectl get storageclass
```

## Deployment Order

**IMPORTANT:** Deploy in this order:

1. CNPG Operator (once per cluster)
2. Encrypt secrets for each environment
3. PostgreSQL clusters (per environment)

## Step 1: Deploy CNPG Operator

The operator must be deployed before any PostgreSQL clusters.

### Option A: Using kubectl (Recommended)

```bash
# Deploy operator via Argo CD Application
kubectl apply -f apps/platform/cnpg-operator/argocd/operator.yaml

# Wait for operator to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=cloudnative-pg \
  -n cnpg-system \
  --timeout=300s
```

### Option B: Using Argo CD UI

1. Navigate to Argo CD UI
2. Click "New App"
3. Fill in:
   - **Application Name**: `cnpg-operator`
   - **Project**: `default`
   - **Repository URL**: `https://github.com/open-liontechsolution/toolsuite-platform-gitops`
   - **Revision**: `main`
   - **Path**: `apps/platform/cnpg-operator`
   - **Cluster URL**: `https://kubernetes.default.svc`
   - **Namespace**: `cnpg-system`
   - **Values Files**: `values.yaml`
4. Enable "Auto-Create Namespace"
5. Enable "Server-Side Apply"
6. Click "Create"

### Option C: Using Helm CLI

```bash
cd apps/platform/cnpg-operator
helm dependency update
helm upgrade --install cnpg-operator . \
  --namespace cnpg-system \
  --create-namespace \
  --values values.yaml
```

### Verify Operator

```bash
# Check operator pod
kubectl get pods -n cnpg-system

# Check operator logs
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg

# Verify CRDs are installed
kubectl get crd | grep cnpg
```

Expected output:
```
backups.postgresql.cnpg.io
clusters.postgresql.cnpg.io
poolers.postgresql.cnpg.io
scheduledbackups.postgresql.cnpg.io
```

## Step 2: Encrypt Secrets

For each environment, encrypt the database credentials.

### Encrypt Username and Password

```bash
# Encrypt username (example for local dev)
echo -n "platform" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace data-dev \
  --name platform-postgres-app

# Encrypt password
echo -n "your-strong-password" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace data-dev \
  --name platform-postgres-app
```

**IMPORTANT:**
- Use `-n` flag with `echo` (no newline)
- Use correct namespace for each environment
- Use strong passwords for production

### Update Environment Values

Edit the environment values file with encrypted values:

```bash
# Edit local dev values
vim apps/data/cnpg/environments/local/dev.yaml
```

Update the `sealedSecret` section:

```yaml
sealedSecret:
  enabled: true
  name: platform-postgres-app
  encryptedData:
    username: "AgAxxxxx..."  # Your encrypted username
    password: "AgAyyyyy..."  # Your encrypted password
```

### Commit Encrypted Values

```bash
git add apps/data/cnpg/environments/local/dev.yaml
git commit -m "Add encrypted secrets for local dev"
git push
```

See [Sealed Secrets Guide](../SEALED-SECRETS-GUIDE.md) for detailed instructions.

## Step 3: Deploy PostgreSQL Cluster

Deploy a PostgreSQL cluster to your chosen environment.

### Option A: Using kubectl (Recommended)

```bash
# Local development
kubectl apply -f apps/data/cnpg/argocd/clusters/local/dev.yaml

# Local QA
kubectl apply -f apps/data/cnpg/argocd/clusters/local/qa.yaml

# Local production
kubectl apply -f apps/data/cnpg/argocd/clusters/local/prod.yaml

# Cloud environments
kubectl apply -f apps/data/cnpg/argocd/clusters/cloud/dev.yaml
kubectl apply -f apps/data/cnpg/argocd/clusters/cloud/qa.yaml
kubectl apply -f apps/data/cnpg/argocd/clusters/cloud/prod.yaml
```

### Option B: Using Argo CD UI

1. Navigate to Argo CD UI
2. Click "New App"
3. Fill in:
   - **Application Name**: `cnpg-cluster-local-dev`
   - **Project**: `default`
   - **Repository URL**: `https://github.com/open-liontechsolution/toolsuite-platform-gitops`
   - **Revision**: `main`
   - **Path**: `apps/data/cnpg`
   - **Cluster URL**: `https://kubernetes.default.svc`
   - **Namespace**: `data-dev`
   - **Values Files**: 
     - `values.yaml`
     - `environments/local/dev.yaml`
   - **Release Name**: `platform-postgres-dev`
4. Enable "Auto-Create Namespace"
5. Enable "Server-Side Apply"
6. Enable "Automated Sync" (for dev/qa)
7. Click "Create"

### Option C: Using Helm CLI

```bash
cd apps/data/cnpg
helm dependency update

# Deploy to local dev
helm upgrade --install platform-postgres-dev . \
  --namespace data-dev \
  --create-namespace \
  --values values.yaml \
  --values environments/local/dev.yaml

# Deploy to local QA
helm upgrade --install platform-postgres-qa . \
  --namespace data-qa \
  --create-namespace \
  --values values.yaml \
  --values environments/local/qa.yaml

# Deploy to local prod
helm upgrade --install platform-postgres-prod . \
  --namespace data-prod \
  --create-namespace \
  --values values.yaml \
  --values environments/local/prod.yaml
```

## Step 4: Verify Deployment

### Check Argo CD Application

```bash
# View Application status
kubectl get application -n argocd cnpg-cluster-local-dev

# Describe Application
kubectl describe application -n argocd cnpg-cluster-local-dev
```

### Check PostgreSQL Cluster

```bash
# View cluster status
kubectl get cluster -n data-dev

# Detailed cluster status
kubectl cnpg status platform-postgres -n data-dev

# Check pods
kubectl get pods -n data-dev

# Check services
kubectl get svc -n data-dev
```

Expected output:
```
NAME                       READY   STATUS    RESTARTS   AGE
platform-postgres-1        1/1     Running   0          2m
```

### Check SealedSecret

```bash
# Check SealedSecret was created
kubectl get sealedsecret -n data-dev

# Check unsealed Secret exists
kubectl get secret platform-postgres-app -n data-dev

# Verify secret has correct keys
kubectl get secret platform-postgres-app -n data-dev -o jsonpath='{.data}' | jq
```

### Check Cluster Health

```bash
# Get cluster details
kubectl get cluster platform-postgres -n data-dev -o yaml

# Check cluster events
kubectl get events -n data-dev --sort-by='.lastTimestamp'

# View operator logs
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg
```

## Step 5: Connect to PostgreSQL

### Get Connection Information

```bash
# Get service name
kubectl get svc -n data-dev

# Get password from secret
kubectl get secret platform-postgres-app -n data-dev \
  -o jsonpath='{.data.password}' | base64 -d
```

### Connect via Port Forward

```bash
# Forward PostgreSQL port
kubectl port-forward -n data-dev svc/platform-postgres-rw 5432:5432

# Connect with psql (in another terminal)
psql -h localhost -p 5432 -U platform -d app
```

### Connect from Pod

```bash
# Run psql in a pod
kubectl run -it --rm psql \
  --image=postgres:16 \
  --restart=Never \
  --namespace=data-dev \
  -- psql -h platform-postgres-rw -U platform -d app
```

## Environment-Specific Deployments

### Local Development (data-dev)

```bash
# Encrypt secrets
echo -n "platform" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace data-dev \
  --name platform-postgres-app

# Deploy
kubectl apply -f apps/data/cnpg/argocd/clusters/local/dev.yaml

# Verify
kubectl get cluster -n data-dev
```

**Configuration:**
- 1 instance
- Minimal resources (250m CPU, 512Mi RAM)
- 20Gi storage
- Longhorn storage class

### Local QA (data-qa)

```bash
# Encrypt secrets
echo -n "platform" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace data-qa \
  --name platform-postgres-app

# Deploy
kubectl apply -f apps/data/cnpg/argocd/clusters/local/qa.yaml

# Verify
kubectl get cluster -n data-qa
```

**Configuration:**
- 2 instances
- Moderate resources (500m CPU, 1Gi RAM)
- 30Gi storage
- Longhorn storage class

### Local Production (data-prod)

```bash
# Encrypt secrets
echo -n "platform" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace data-prod \
  --name platform-postgres-app

# Deploy (manual sync required)
kubectl apply -f apps/data/cnpg/argocd/clusters/local/prod.yaml

# Manually sync in Argo CD UI or:
argocd app sync cnpg-cluster-local-prod
```

**Configuration:**
- 3 instances (HA)
- Production resources (1 CPU, 2Gi RAM)
- 50Gi storage
- Longhorn storage class
- Manual sync policy

### Cloud Environments

Similar process but with cloud-specific storage classes:

```bash
# Deploy cloud dev
kubectl apply -f apps/data/cnpg/argocd/clusters/cloud/dev.yaml
```

**Configuration:**
- AWS: `gp3` storage class
- GCP: `pd-ssd` storage class
- Azure: `managed-premium` storage class

## Updating Deployments

### Update Configuration

```bash
# Edit environment values
vim apps/data/cnpg/environments/local/dev.yaml

# Commit changes
git add apps/data/cnpg/environments/local/dev.yaml
git commit -m "Update dev configuration"
git push

# Argo CD will automatically sync (if enabled)
# Or manually sync:
argocd app sync cnpg-cluster-local-dev
```

### Update Secrets

```bash
# Encrypt new password
echo -n "new-password" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace data-dev \
  --name platform-postgres-app

# Update values file
vim apps/data/cnpg/environments/local/dev.yaml

# Commit and push
git add apps/data/cnpg/environments/local/dev.yaml
git commit -m "Update dev secrets"
git push
```

## Uninstalling

### Remove Cluster

```bash
# Delete Argo CD Application
kubectl delete application cnpg-cluster-local-dev -n argocd

# Or delete cluster directly
kubectl delete cluster platform-postgres -n data-dev

# Delete namespace
kubectl delete namespace data-dev
```

### Remove Operator

```bash
# Delete operator Application
kubectl delete application cnpg-operator -n argocd

# Or delete operator directly
helm uninstall cnpg-operator -n cnpg-system

# Delete namespace
kubectl delete namespace cnpg-system
```

## Troubleshooting

See [Troubleshooting Guide](troubleshooting.md) for common issues and solutions.

## Next Steps

- [Configure backups](../apps/data/cnpg/README.md#backups)
- [Set up monitoring](../apps/data/cnpg/README.md#monitoring)
- [Configure connection pooling](../apps/data/cnpg/README.md#pooling)
- [Review security settings](../SEALED-SECRETS-GUIDE.md)

## References

- [CNPG Cluster Chart](../../apps/data/cnpg/README.md)
- [CNPG Operator Chart](../../apps/platform/cnpg-operator/README.md)
- [Environment Configuration](../../apps/data/cnpg/environments/README.md)
- [Argo CD Applications](../../apps/data/cnpg/argocd/README.md)
- [Sealed Secrets Guide](../SEALED-SECRETS-GUIDE.md)
