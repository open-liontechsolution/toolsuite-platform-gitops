# Cloud Overlay

This overlay provides cloud-specific configurations for the platform. Customize the patches in `kustomization.yaml` based on your cloud provider.

## Common Cloud Configurations

### AWS
- **Storage class:** `gp3` (general purpose SSD) or `io2` (high performance)
- **CSI driver:** EBS CSI driver (usually pre-installed on EKS)
- **Recommendations:**
  - Use 3+ availability zones for HA
  - Consider using EBS snapshots for additional backup strategy
  - Enable encryption at rest for production workloads

### GCP
- **Storage class:** `pd-ssd` (SSD persistent disk) or `pd-balanced`
- **CSI driver:** GCE Persistent Disk CSI driver (pre-installed on GKE)
- **Recommendations:**
  - Use regional persistent disks for HA across zones
  - Consider using Cloud SQL for managed PostgreSQL (alternative to CNPG)
  - Enable automatic disk resizing

### Azure
- **Storage class:** `managed-premium` (Premium SSD) or `managed-csi`
- **CSI driver:** Azure Disk CSI driver (pre-installed on AKS)
- **Recommendations:**
  - Use zone-redundant storage (ZRS) for production
  - Consider Azure Database for PostgreSQL (alternative to CNPG)
  - Enable disk encryption

## Typical Changes

1. **Storage Class**: Replace `standard` with cloud-specific storage class
2. **Resources**: Increase CPU/memory for production workloads
3. **Backup Storage**: Increase backup PVC size (100Gi+ recommended)
4. **Node Affinity**: Add tolerations for dedicated database node pools
5. **Backup Schedule**: Adjust CronJob schedule based on RTO/RPO requirements

## Activation

Uncomment and customize the patches in `kustomization.yaml`, then apply via Argo CD or:

```bash
kustomize build clusters/cloud | kubectl apply -f -
```

## Example Production Configuration

For a production environment, you might want:

- **PostgreSQL instances:** 3 (HA across zones)
- **CPU/Memory:** 2-4 CPU, 4-8Gi memory per instance
- **Storage:** 100Gi+ for database, 200Gi+ for backups
- **Backup frequency:** Every 6 hours or more frequent
- **Monitoring:** Enable CloudNativePG metrics and integrate with Prometheus

See the commented examples in `kustomization.yaml` for implementation details.
