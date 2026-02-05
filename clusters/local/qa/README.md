# Local QA Environment

PostgreSQL cluster deployment for local k3s QA environment.

## Configuration

- **Namespace:** `data-qa`
- **Instances:** 2 (high availability)
- **Storage:** Longhorn, 30Gi
- **Resources:** 500m CPU / 1Gi RAM (limits: 2 CPU / 3Gi RAM)

## Prerequisites

1. CloudNativePG operator installed (see `apps/platform/cnpg-operator/`)
2. Longhorn storage class available
3. Application secret created in `data-qa` namespace

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
  --namespace data-qa \
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

## Deployment

### Using Helm CLI

```bash
cd ../../..  # Return to repo root
helm dependency update apps/data/cnpg
helm upgrade --install platform-postgres-qa apps/data/cnpg \
  --namespace data-qa \
  --create-namespace \
  --values apps/data/cnpg/values.yaml \
  --values apps/data/cnpg/values-local-qa.yaml
```

### Using Argo CD

Apply the Argo CD Application manifest (see `argocd/` directory in repo root).

## Verification

```bash
# Check cluster status
kubectl get cluster -n data-qa
kubectl cnpg status platform-postgres -n data-qa

# Check pods (should see 2 instances)
kubectl get pods -n data-qa

# Check services
kubectl get svc -n data-qa

# Check PVCs
kubectl get pvc -n data-qa
```

## Connecting to Database

### Port-forward

```bash
kubectl port-forward -n data-qa svc/platform-postgres-rw 5432:5432
```

Then connect:
```bash
psql -h localhost -U platform -d platform
```

## Notes

- Two-instance deployment provides high availability
- Node affinity prefers nodes with `workload=db` label
- Configure backups for QA data retention if needed
