# Cloud Production Environment

This overlay deploys PostgreSQL to the `data-prod` namespace in a cloud Kubernetes cluster (EKS/GKE/AKS).

## Configuration

- **Namespace:** `data-prod`
- **Instances:** 3 (full HA across zones)
- **Resources:** 2 CPU, 4Gi RAM (limits: 8 CPU, 16Gi RAM)
- **Storage:** Cloud storage class (gp3/pd-ssd/managed-premium, 200Gi backup volume)

## Creating Your Secret

1. Copy the example secret:
   ```bash
   cp ../../../apps/data/cnpg/secret-app.example.yaml secret-app.yaml
   ```

2. Edit `secret-app.yaml` and set a **strong production password**

3. Encrypt with kubeseal:
   ```bash
   kubeseal --format=yaml \
     --namespace data-prod \
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
kustomize build clusters/cloud/prod | kubectl apply -f -
```

## Important

- Use a strong, unique password for production
- Ensure cloud storage class is properly configured
- Monitor costs and resource usage
- Enable encryption at rest for production data
