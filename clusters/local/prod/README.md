# Local Production Environment

PostgreSQL cluster deployment for local k3s production environment.

## Configuration

- **Namespace:** `data-prod`
- **Instances:** 3 (full high availability)
- **Storage:** Longhorn, 50Gi
- **Resources:** 1 CPU / 2Gi RAM (limits: 4 CPU / 8Gi RAM)

## Prerequisites

1. CloudNativePG operator installed (see `apps/platform/cnpg-operator/`)
2. Longhorn storage class available
3. Application secret created in `data-prod` namespace
4. At least 3 nodes for proper pod distribution

## Create Application Secret

### Using Sealed Secrets (Required for Production)

1. Copy the example secret:
```bash
cp secrets/secret-app.example.yaml secrets/secret-app.yaml
```

2. Edit `secrets/secret-app.yaml` and set a **strong** password

3. Encrypt with kubeseal:
```bash
kubeseal --format=yaml \
  --namespace data-prod \
  < secrets/secret-app.yaml \
  > secrets/sealedsecret-app.yaml
```

4. Apply the sealed secret:
```bash
kubectl apply -f secrets/sealedsecret-app.yaml
```

5. **Delete the plain secret immediately:**
```bash
rm secrets/secret-app.yaml
```

## Deployment

### Using Helm CLI

```bash
cd ../../..  # Return to repo root
helm dependency update apps/data/cnpg
helm upgrade --install platform-postgres-prod apps/data/cnpg \
  --namespace data-prod \
  --create-namespace \
  --values apps/data/cnpg/values.yaml \
  --values clusters/local/prod/values.yaml
```

### Using Argo CD (Recommended)

Apply the Argo CD Application manifest (see `argocd/` directory in repo root).

## Verification

```bash
# Check cluster status
kubectl get cluster -n data-prod
kubectl cnpg status platform-postgres -n data-prod

# Check pods (should see 3 instances)
kubectl get pods -n data-prod -o wide

# Verify pod distribution across nodes
kubectl get pods -n data-prod -o wide | grep platform-postgres

# Check services
kubectl get svc -n data-prod

# Check PVCs
kubectl get pvc -n data-prod
```

## Connecting to Database

### Port-forward

```bash
kubectl port-forward -n data-prod svc/platform-postgres-rw 5432:5432
```

Then connect:
```bash
psql -h localhost -U platform -d platform
```

## Backup Configuration

**Important:** Configure backups for production data:

1. Edit `apps/data/cnpg/values-local-prod.yaml`
2. Enable and configure backup settings
3. Consider using both:
   - CNPG native backups (to S3/MinIO)
   - Longhorn snapshots (for disaster recovery)

## Monitoring

Enable monitoring by updating `values-local-prod.yaml`:

```yaml
cluster:
  monitoring:
    enabled: true
    podMonitorEnabled: true
```

## Notes

- Three-instance deployment provides full high availability
- Node affinity prefers nodes with `workload=db` label
- Anti-affinity ensures pods are distributed across different nodes
- **Always use sealed secrets** - never plain secrets in production
- Configure regular backups and test restore procedures
- Monitor database performance and adjust resources as needed
