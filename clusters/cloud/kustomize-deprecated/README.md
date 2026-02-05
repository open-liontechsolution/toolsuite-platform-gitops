# Cloud Cluster Overlays

This directory contains Kustomize overlays for **cloud Kubernetes deployments** (EKS, GKE, AKS) using cloud-native storage providers.

## Available Environments

### Development (`dev/`)
- **Instances:** 2 PostgreSQL instances (HA)
- **Resources:** 500m CPU, 1Gi RAM (limits: 2 CPU, 4Gi RAM)
- **Storage:** 50Gi backup volume
- **Use case:** Cloud development, testing, staging

### QA (`qa/`)
- **Instances:** 2 PostgreSQL instances (HA)
- **Resources:** 1 CPU, 2Gi RAM (limits: 3 CPU, 6Gi RAM)
- **Storage:** 75Gi backup volume
- **Use case:** Pre-production testing, QA validation

### Production (`prod/`)
- **Instances:** 3 PostgreSQL instances (full HA across zones)
- **Resources:** 2 CPU, 4Gi RAM (limits: 8 CPU, 16Gi RAM)
- **Storage:** 200Gi backup volume
- **Use case:** Production workloads with high availability

## Cloud Provider Configuration

Each environment is pre-configured with `gp3` storage class (AWS default). Customize based on your provider:

### AWS (EKS)
```yaml
storageClass: gp3  # or io2 for high performance
```
- **CSI driver:** EBS CSI driver (pre-installed)
- **Recommendations:** Use 3+ availability zones, enable encryption at rest

### GCP (GKE)
```yaml
storageClass: pd-ssd  # or pd-balanced
```
- **CSI driver:** GCE Persistent Disk CSI driver (pre-installed)
- **Recommendations:** Use regional persistent disks for HA

### Azure (AKS)
```yaml
storageClass: managed-premium  # or managed-csi
```
- **CSI driver:** Azure Disk CSI driver (pre-installed)
- **Recommendations:** Use zone-redundant storage (ZRS)

## Prerequisites

- Cloud Kubernetes cluster (EKS/GKE/AKS)
- Cloud storage CSI driver installed
- kubectl configured to access the cluster
- (Optional) Argo CD for GitOps deployment

## Deployment

### Using kubectl + kustomize

```bash
# Deploy development environment
kustomize build clusters/cloud/dev | kubectl apply -f -

# Deploy QA environment
kustomize build clusters/cloud/qa | kubectl apply -f -

# Deploy production environment
kustomize build clusters/cloud/prod | kubectl apply -f -
```

### Using Argo CD

Create an Application pointing to the desired environment:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: data-cnpg-cloud-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<your-org>/toolsuite-platform-gitops
    path: clusters/cloud/prod
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: data-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

## Customization

To adapt for your cloud provider, edit the environment's `kustomization.yaml`:

1. **Change storage class:**
   ```yaml
   - op: replace
     path: /spec/storage/storageClass
     value: pd-ssd  # or your cloud's storage class
   ```

2. **Adjust resources:**
   ```yaml
   - op: add
     path: /spec/resources
     value:
       requests:
         cpu: "4"
         memory: "8Gi"
   ```

3. **Add node affinity/tolerations:**
   ```yaml
   - op: add
     path: /spec/affinity/nodeAffinity
     value:
       requiredDuringSchedulingIgnoredDuringExecution:
         nodeSelectorTerms:
           - matchExpressions:
               - key: workload
                 operator: In
                 values:
                   - database
   ```

## Verification

After deployment:

```bash
# Check CNPG operator
kubectl get pods -n cnpg-system

# Check PostgreSQL cluster
kubectl get cluster -n data-system
kubectl get pods -n data-system

# Check services
kubectl get svc -n data-system

# Check backups
kubectl get cronjob -n data-system
kubectl get pvc -n data-system

# Check pod distribution across zones
kubectl get pods -n data-system -o wide
```

## Production Considerations

- **Multi-AZ deployment:** Ensure nodes are spread across availability zones
- **Backup strategy:** Combine logical backups with cloud snapshots
- **Monitoring:** Integrate CNPG metrics with Prometheus/CloudWatch/Stackdriver
- **Security:** Enable encryption at rest and in transit
- **Cost optimization:** Right-size resources based on actual usage

## Notes

- All environments include automated logical backups via CronJob
- Cloud providers offer additional snapshot/backup capabilities
- Production environment is configured for high availability across zones
- Consider using managed PostgreSQL services (RDS/Cloud SQL/Azure Database) for simpler operations
