# Local Production Environment

This overlay deploys PostgreSQL to the `data-prod` namespace in a local k3s cluster.

## Configuration

- **Namespace:** `data-prod`
- **Instances:** 3 (full HA)
- **Resources:** 1 CPU, 2Gi RAM (limits: 4 CPU, 8Gi RAM)
- **Storage:** Longhorn (50Gi backup volume)

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
kustomize build clusters/local/prod | kubectl apply -f -
```

## Important

- Use a strong, unique password for production
- Ensure Longhorn has sufficient storage capacity
- Monitor resource usage and adjust as needed
