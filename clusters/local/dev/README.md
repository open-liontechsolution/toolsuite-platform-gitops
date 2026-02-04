# Local Dev Environment

This overlay deploys PostgreSQL to the `data-dev` namespace in a local k3s cluster.

## Configuration

- **Namespace:** `data-dev`
- **Instances:** 1 (minimal for development)
- **Resources:** 250m CPU, 512Mi RAM (limits: 1 CPU, 2Gi RAM)
- **Storage:** Longhorn (20Gi backup volume)

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

4. Uncomment the secret reference in `kustomization.yaml`:
   ```yaml
   resources:
     - ../../../apps/data/cnpg
     - sealedsecret-app.yaml  # Uncomment this line
   ```

5. Delete the plain secret:
   ```bash
   rm secret-app.yaml
   ```

## Deployment

```bash
kustomize build clusters/local/dev | kubectl apply -f -
```

## Verification

```bash
kubectl get all -n data-dev
kubectl get cluster -n data-dev
```
