# Local Development Environment

PostgreSQL cluster deployment for local k3s development environment.

## Configuration

- **Namespace:** `data-dev`
- **Instances:** 1 (single instance for development)
- **Storage:** Longhorn, 20Gi
- **Resources:** 250m CPU / 512Mi RAM (limits: 1 CPU / 2Gi RAM)

## Prerequisites

1. CloudNativePG operator installed (see `apps/platform/cnpg-operator/`)
2. Longhorn storage class available
3. Application secret created in `data-dev` namespace

## Create Application Secret

### Using Sealed Secrets (Recommended)

1. Copy the example secret:
```bash
cp secrets/secret-app.example.yaml secrets/secret-app.yaml
```

2. Edit `secrets/secret-app.yaml` and set a strong password

3. Encrypt with kubeseal:
```bash
kubeseal --format=yaml \
  --namespace data-dev \
  < secrets/secret-app.yaml \
  > secrets/sealedsecret-app.yaml
```

4. Apply the sealed secret:
```bash
kubectl apply -f secrets/sealedsecret-app.yaml
```

5. Delete the plain secret:
```bash
rm secrets/secret-app.yaml
```

### Using kubectl (Development Only)

```bash
kubectl create secret generic platform-postgres-app \
  --namespace data-dev \
  --from-literal=username=platform \
  --from-literal=password=your-dev-password
```

## Deployment

### Using Helm CLI

```bash
cd ../../..  # Return to repo root
helm dependency update apps/data/cnpg
helm upgrade --install platform-postgres-dev apps/data/cnpg \
  --namespace data-dev \
  --create-namespace \
  --values apps/data/cnpg/values.yaml \
  --values apps/data/cnpg/values-local-dev.yaml
```

### Using Argo CD

Apply the Argo CD Application manifest (see `argocd/` directory in repo root).

## Verification

```bash
# Check cluster status
kubectl get cluster -n data-dev
kubectl cnpg status platform-postgres -n data-dev

# Check pods
kubectl get pods -n data-dev

# Check services
kubectl get svc -n data-dev

# Check PVCs
kubectl get pvc -n data-dev
```

## Connecting to Database

### Port-forward

```bash
kubectl port-forward -n data-dev svc/platform-postgres-rw 5432:5432
```

Then connect:
```bash
psql -h localhost -U platform -d platform
```

### Get Password

```bash
kubectl get secret platform-postgres-app -n data-dev \
  -o jsonpath='{.data.password}' | base64 -d
```

## Notes

- This is a single-instance deployment suitable for development only
- Node affinity prefers nodes with `node.kubernetes.io/performance=high` label
- No backups are configured by default (add if needed)
