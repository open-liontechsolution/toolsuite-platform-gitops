# Cloud Cluster Deployments

PostgreSQL cluster deployments for **cloud Kubernetes** (EKS, GKE, AKS) using cloud-native storage.

## Overview

This directory contains Helm-based configurations for deploying CloudNativePG PostgreSQL clusters to cloud Kubernetes environments. Each environment is optimized for cloud-native high availability.

## Available Environments

| Environment | Namespace | Instances | CPU/Memory | Storage | Use Case |
|-------------|-----------|-----------|------------|---------|----------|
| **dev**     | data-dev  | 2         | 500m/1Gi   | 50Gi    | Cloud development |
| **qa**      | data-qa   | 2         | 1/2Gi      | 75Gi    | Pre-production testing |
| **prod**    | data-prod | 3         | 2/4Gi      | 200Gi   | Production workloads |

## Prerequisites

- Cloud Kubernetes cluster (EKS/GKE/AKS)
- Cloud storage CSI driver installed
- CloudNativePG operator deployed (see `apps/platform/cnpg-operator/`)
- kubectl and Helm 3.x installed
- (Optional) Backup storage configured (S3/GCS/Azure Blob)

## Cloud Provider Configuration

### AWS (EKS)
- **Storage Class:** `gp3` (default) or `io2` for high performance
- **CSI Driver:** EBS CSI driver (pre-installed)
- **Recommendations:** Use 3+ availability zones, enable encryption at rest

### GCP (GKE)
- **Storage Class:** `pd-ssd` or `pd-balanced`
- **CSI Driver:** GCE Persistent Disk CSI driver (pre-installed)
- **Recommendations:** Use regional persistent disks for HA

### Azure (AKS)
- **Storage Class:** `managed-premium` or `managed-csi`
- **CSI Driver:** Azure Disk CSI driver (pre-installed)
- **Recommendations:** Use zone-redundant storage (ZRS)

## Quick Start

1. **Deploy the operator** (once per cluster):
```bash
cd apps/platform/cnpg-operator
helm dependency update
helm upgrade --install cnpg-operator . \
  --namespace cnpg-system \
  --create-namespace
```

2. **Adjust storage class** if not using AWS:
Edit `apps/data/cnpg/values-cloud-{env}.yaml` and change `storageClass`:
```yaml
cluster:
  storage:
    storageClass: pd-ssd  # For GCP
    # or managed-premium  # For Azure
```

3. **Create application secret** for your environment:
```bash
cd clusters/cloud/dev  # or qa/prod
cp secrets/secret-app.example.yaml secrets/secret-app.yaml
# Edit and set password
kubeseal --format=yaml --namespace data-dev \
  < secrets/secret-app.yaml > secrets/sealedsecret-app.yaml
kubectl apply -f secrets/sealedsecret-app.yaml
rm secrets/secret-app.yaml
```

4. **Deploy PostgreSQL cluster**:
```bash
cd ../../..  # Return to repo root
helm dependency update apps/data/cnpg
helm upgrade --install platform-postgres-dev apps/data/cnpg \
  --namespace data-dev \
  --create-namespace \
  --values apps/data/cnpg/values.yaml \
  --values apps/data/cnpg/values-cloud-dev.yaml
```

## Multi-AZ High Availability

All cloud environments use `topology.kubernetes.io/zone` for anti-affinity:
- **Dev/QA:** Preferred anti-affinity (2 instances across zones)
- **Prod:** Required anti-affinity (3 instances, must be in different zones)

Ensure your cluster has nodes in multiple availability zones.

## Verification

```bash
# Check operator
kubectl get pods -n cnpg-system

# Check cluster (replace data-dev with your namespace)
kubectl get cluster -n data-dev
kubectl cnpg status platform-postgres -n data-dev

# Check pod distribution across zones
kubectl get pods -n data-dev -o wide

# Check services
kubectl get svc -n data-dev
```

## Environment Details

### Development (dev/)
- Two instances across availability zones
- Moderate resources for cloud development
- See `dev/README.md` for details

### QA (qa/)
- Two instances across availability zones
- Increased resources for testing
- See `qa/README.md` for details

### Production (prod/)
- Three instances across availability zones
- Production-grade resources and configuration
- Backup and monitoring recommended
- See `prod/README.md` for details

## Backup Configuration

For production environments, configure cloud-native backups:

1. **Create backup credentials secret:**
```bash
# AWS S3
kubectl create secret generic backup-credentials \
  --namespace data-prod \
  --from-literal=ACCESS_KEY_ID=your-key \
  --from-literal=ACCESS_SECRET_KEY=your-secret

# GCP GCS (use service account key)
kubectl create secret generic backup-credentials \
  --namespace data-prod \
  --from-file=APPLICATION_CREDENTIALS=service-account.json

# Azure Blob
kubectl create secret generic backup-credentials \
  --namespace data-prod \
  --from-literal=AZURE_STORAGE_ACCOUNT=account \
  --from-literal=AZURE_STORAGE_KEY=key
```

2. **Enable backups** in `values-cloud-prod.yaml`:
```yaml
cluster:
  backup:
    enabled: true
    barmanObjectStore:
      destinationPath: s3://your-bucket/backups
      # Configure credentials
  scheduledBackup:
    enabled: true
    schedule: "0 2 * * *"
```

## Monitoring

Enable Prometheus monitoring for production:

```yaml
cluster:
  monitoring:
    enabled: true
    podMonitorEnabled: true
```

Integrate with your cloud monitoring solution:
- **AWS:** CloudWatch Container Insights
- **GCP:** Google Cloud Monitoring (Stackdriver)
- **Azure:** Azure Monitor for containers

## Cost Optimization

- Right-size resources based on actual usage
- Use appropriate storage classes (gp3 vs io2)
- Configure backup retention policies
- Consider using spot/preemptible nodes for non-prod
- Monitor and adjust PostgreSQL connection pooling

## Migration from Kustomize

Previous Kustomize configurations are preserved in `kustomize-deprecated/` for reference. The new Helm-based approach provides:
- Official CloudNativePG chart support
- Better cloud-native integration
- Easier multi-environment management

See the main repository's `MIGRATION.md` for migration instructions.

## Troubleshooting

### Storage Issues
```bash
kubectl get storageclass
kubectl describe pvc -n data-dev
```

### Multi-AZ Distribution
```bash
kubectl get pods -n data-dev -o wide
kubectl get nodes --show-labels | grep topology.kubernetes.io/zone
```

### Backup Issues
```bash
kubectl get backup -n data-prod
kubectl describe backup -n data-prod
```

## Security Considerations

- Enable encryption at rest (cloud storage encryption)
- Enable encryption in transit (TLS certificates)
- Use sealed secrets or external secret managers
- Implement network policies
- Enable audit logging
- Regular security updates

## References

- [CloudNativePG Documentation](https://cloudnative-pg.io/)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [GKE Best Practices](https://cloud.google.com/kubernetes-engine/docs/best-practices)
- [AKS Best Practices](https://learn.microsoft.com/en-us/azure/aks/best-practices)
