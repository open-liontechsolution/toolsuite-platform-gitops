# Cloud Development Environment

PostgreSQL cluster deployment for cloud Kubernetes (EKS/GKE/AKS) development environment.

## Configuration

- **Namespace:** `data-dev`
- **Instances:** 2 (high availability)
- **Storage:** Cloud-native (gp3/pd-ssd/managed-premium), 50Gi
- **Resources:** 500m CPU / 1Gi RAM (limits: 2 CPU / 4Gi RAM)

## Prerequisites

1. CloudNativePG operator installed (see `apps/platform/cnpg-operator/`)
2. Cloud storage CSI driver configured
3. Application secret created in `data-dev` namespace

## Storage Class Configuration

The default storage class is `gp3` (AWS). Adjust in `apps/data/cnpg/values-cloud-dev.yaml` for your cloud provider:

- **AWS (EKS):** `gp3` or `io2`
- **GCP (GKE):** `pd-ssd` or `pd-balanced`
- **Azure (AKS):** `managed-premium` or `managed-csi`

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

## Deployment

### Using Helm CLI

```bash
cd ../../..  # Return to repo root
helm dependency update apps/data/cnpg
helm upgrade --install platform-postgres-dev apps/data/cnpg \
  --namespace data-dev \
  --create-namespace \
  --values apps/data/cnpg/values.yaml \
  --values clusters/cloud/dev/values.yaml
```

### Using Argo CD

Apply the Argo CD Application manifest (see `argocd/` directory in repo root).

## Verification

```bash
# Check cluster status
kubectl get cluster -n data-dev
kubectl cnpg status platform-postgres -n data-dev

# Check pods (should see 2 instances)
kubectl get pods -n data-dev -o wide

# Verify multi-AZ distribution
kubectl get pods -n data-dev -o wide | grep platform-postgres

# Check services
kubectl get svc -n data-dev

# Check PVCs
kubectl get pvc -n data-dev
```

## Notes

- Two-instance deployment provides high availability across availability zones
- Anti-affinity uses `topology.kubernetes.io/zone` for multi-AZ distribution
- Node affinity prefers nodes with `workload=database` label
- Consider enabling cloud-native backups to S3/GCS/Azure Blob
