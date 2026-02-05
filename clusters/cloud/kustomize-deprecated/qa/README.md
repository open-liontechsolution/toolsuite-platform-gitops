# Cloud QA Environment

This overlay deploys PostgreSQL to the `data-qa` namespace in a cloud Kubernetes cluster (EKS/GKE/AKS).

## Configuration

- **Namespace:** `data-qa`
- **Instances:** 2 (HA)
- **Resources:** 1 CPU, 2Gi RAM (limits: 3 CPU, 6Gi RAM)
- **Storage:** Cloud storage class (gp3/pd-ssd/managed-premium, 75Gi backup volume)

## Creating Your Secret

1. Copy the example secret:
   ```bash
   cp ../../../apps/data/cnpg/secret-app.example.yaml secret-app.yaml
   ```

2. Edit `secret-app.yaml` and set a strong password

3. Encrypt with kubeseal:
   ```bash
   kubeseal --format=yaml \
     --namespace data-qa \
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
kustomize build clusters/cloud/qa | kubectl apply -f -
```
