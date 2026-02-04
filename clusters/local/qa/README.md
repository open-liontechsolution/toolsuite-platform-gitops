# Local QA Environment

This overlay deploys PostgreSQL to the `data-qa` namespace in a local k3s cluster.

## Configuration

- **Namespace:** `data-qa`
- **Instances:** 2 (HA for testing)
- **Resources:** 500m CPU, 1Gi RAM (limits: 2 CPU, 3Gi RAM)
- **Storage:** Longhorn (30Gi backup volume)

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
kustomize build clusters/local/qa | kubectl apply -f -
```
