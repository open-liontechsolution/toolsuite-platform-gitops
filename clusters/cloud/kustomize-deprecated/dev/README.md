# Cloud Dev Environment

This overlay deploys PostgreSQL to the `data-dev` namespace in a cloud Kubernetes cluster (EKS/GKE/AKS).

## Configuration

- **Namespace:** `data-dev`
- **Instances:** 2 (HA for cloud)
- **Resources:** 500m CPU, 1Gi RAM (limits: 2 CPU, 4Gi RAM)
- **Storage:** Cloud storage class (gp3/pd-ssd/managed-premium, 50Gi backup volume)

## Creating Your Secret

1. Copy the example secret:
   ```bash
   cp ../../../apps/data/cnpg/secret-app.example.yaml secret-app.yaml
   ```

2. Edit `secret-app.yaml` and set a strong password

3. Encrypt with kubeseal:
   ```bash
   kubeseal --format=yaml \
     --namespace data-dev \
     < secret-app.yaml \
     > sealedsecret-app.yaml
   ```

4. Uncomment the secret reference in `kustomization.yaml`

5. Delete the plain secret:
   ```bash
   rm secret-app.yaml
   ```

## Deployment

```bash
kustomize build clusters/cloud/dev | kubectl apply -f -
```

## Verification

```bash
kubectl get all -n data-dev
kubectl get cluster -n data-dev
```
