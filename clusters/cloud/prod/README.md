# Cloud Production Environment

PostgreSQL cluster deployment for cloud Kubernetes (EKS/GKE/AKS) production environment.

## Configuration

- **Namespace:** `data-prod`
- **Instances:** 3 (full high availability across zones)
- **Storage:** Cloud-native (gp3/pd-ssd/managed-premium), 200Gi
- **Resources:** 2 CPU / 4Gi RAM (limits: 8 CPU / 16Gi RAM)

## Prerequisites

1. CloudNativePG operator installed (see `apps/platform/cnpg-operator/`)
2. Cloud storage CSI driver configured
3. Application secret created in `data-prod` namespace
4. Cluster with at least 3 availability zones
5. Backup storage configured (S3/GCS/Azure Blob)

## Storage Class Configuration

The default storage class is `gp3` (AWS). Adjust in `apps/data/cnpg/values-cloud-prod.yaml` for your cloud provider:

- **AWS (EKS):** `gp3` or `io2` (with encryption)
- **GCP (GKE):** `pd-ssd` (regional disks recommended)
- **Azure (AKS):** `managed-premium` (with ZRS)

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
  --values clusters/cloud/prod/values.yaml
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

# Verify multi-AZ distribution (should be in different zones)
kubectl get pods -n data-prod -o wide | grep platform-postgres

# Check services
kubectl get svc -n data-prod

# Check PVCs
kubectl get pvc -n data-prod
```

## Backup Configuration

**Critical:** Configure cloud-native backups for production:

1. Create backup credentials secret:
```bash
kubectl create secret generic backup-credentials \
  --namespace data-prod \
  --from-literal=ACCESS_KEY_ID=your-key \
  --from-literal=ACCESS_SECRET_KEY=your-secret
```

2. Edit `apps/data/cnpg/values-cloud-prod.yaml` and enable backup:
```yaml
cluster:
  backup:
    enabled: true
    barmanObjectStore:
      destinationPath: s3://your-bucket/prod-backups
      # Configure credentials and encryption
  scheduledBackup:
    enabled: true
    schedule: "0 2 * * *"
```

3. Test backup and restore procedures regularly

## Monitoring

Enable monitoring by updating `values-cloud-prod.yaml`:

```yaml
cluster:
  monitoring:
    enabled: true
    podMonitorEnabled: true
```

Integrate with your cloud monitoring solution (CloudWatch/Stackdriver/Azure Monitor).

## High Availability

- **Three instances** distributed across availability zones
- **Required anti-affinity** ensures pods never run in the same zone
- **Automatic failover** managed by CloudNativePG operator
- **Read replicas** available via `platform-postgres-ro` service

## Security Considerations

- Enable encryption at rest (cloud storage encryption)
- Enable encryption in transit (TLS certificates)
- Use strong passwords and rotate regularly
- Implement network policies to restrict access
- Enable audit logging
- Regular security updates

## Disaster Recovery

1. **Automated backups** to cloud object storage
2. **Point-in-time recovery** capability
3. **Cross-region replication** (configure if needed)
4. **Regular restore testing** (monthly recommended)

## Notes

- Three-instance deployment provides full high availability across zones
- Anti-affinity is **required** (not preferred) for production
- **Always use sealed secrets** - never plain secrets in production
- Configure and test backups before going live
- Monitor database performance and set up alerts
- Plan for capacity growth and resource scaling
- Document incident response procedures
