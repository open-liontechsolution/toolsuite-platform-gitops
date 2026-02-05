# SealedSecrets Management Guide

This guide explains how to manage encrypted secrets for CloudNativePG clusters using Bitnami Sealed Secrets.

## Overview

Secrets are now managed through the Helm chart using a SealedSecret template. This approach:

- ✅ **Keeps secrets in Git** - Encrypted values are safe to commit
- ✅ **Single deployment** - Secrets are deployed with the cluster via Argo CD
- ✅ **Environment-specific** - Each environment has its own encrypted secrets
- ✅ **GitOps-friendly** - No manual kubectl apply needed

## How It Works

1. **Template**: The Helm chart contains a SealedSecret template at `apps/data/cnpg/templates/sealedsecret.yaml`
2. **Values**: Each environment's `values.yaml` contains encrypted secret data
3. **Deployment**: When Argo CD deploys the cluster, it also creates the SealedSecret
4. **Unsealing**: The sealed-secrets controller automatically unseals it into a regular Secret

## Prerequisites

1. **Sealed Secrets Controller** must be installed in your cluster:
   ```bash
   helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
   helm install sealed-secrets sealed-secrets/sealed-secrets \
     --namespace kube-system \
     --create-namespace
   ```

2. **kubeseal CLI** must be installed locally:
   ```bash
   # macOS
   brew install kubeseal
   
   # Linux
   wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz
   tar xfz kubeseal-0.24.0-linux-amd64.tar.gz
   sudo install -m 755 kubeseal /usr/local/bin/kubeseal
   ```

## Encrypting Secrets

### Step 1: Encrypt Your Values

For each environment, you need to encrypt the username and password:

```bash
# Encrypt username for local dev
echo -n "platform" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace data-dev \
  --name platform-postgres-app

# Output: AgAxxxxxxxxxxxxxxxxxxxxx...

# Encrypt password for local dev
echo -n "your-strong-password" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace data-dev \
  --name platform-postgres-app

# Output: AgByyyyyyyyyyyyyyyyyyyyyy...
```

**Important Notes:**
- Use the correct `--namespace` for each environment (data-dev, data-qa, data-prod)
- The `--name` must match the secret name: `platform-postgres-app`
- The `-n` flag in `echo` is critical (no newline)

### Step 2: Update Values File

Edit the environment's values file with the encrypted values:

```yaml
# clusters/local/dev/values.yaml
sealedSecret:
  enabled: true
  name: platform-postgres-app
  encryptedData:
    username: "AgAxxxxxxxxxxxxxxxxxxxxx..."  # Your encrypted username
    password: "AgByyyyyyyyyyyyyyyyyyyyyy..."  # Your encrypted password
```

### Step 3: Commit and Push

```bash
git add clusters/local/dev/values.yaml
git commit -m "Add encrypted secrets for local dev"
git push
```

### Step 4: Deploy via Argo CD

The Application will now deploy both the cluster and the sealed secret:

```bash
kubectl apply -f argocd/clusters/local/cnpg-cluster-dev.yaml
```

## Environment-Specific Instructions

### Local Dev (data-dev namespace)

```bash
# Encrypt secrets
USERNAME_ENC=$(echo -n "platform" | kubeseal --raw --from-file=/dev/stdin --namespace data-dev --name platform-postgres-app)
PASSWORD_ENC=$(echo -n "dev-password-123" | kubeseal --raw --from-file=/dev/stdin --namespace data-dev --name platform-postgres-app)

# Update clusters/local/dev/values.yaml
# Then commit and push
```

### Local QA (data-qa namespace)

```bash
# Encrypt secrets
USERNAME_ENC=$(echo -n "platform" | kubeseal --raw --from-file=/dev/stdin --namespace data-qa --name platform-postgres-app)
PASSWORD_ENC=$(echo -n "qa-password-456" | kubeseal --raw --from-file=/dev/stdin --namespace data-qa --name platform-postgres-app)

# Update clusters/local/qa/values.yaml
# Then commit and push
```

### Local Prod (data-prod namespace)

```bash
# Encrypt secrets
USERNAME_ENC=$(echo -n "platform" | kubeseal --raw --from-file=/dev/stdin --namespace data-prod --name platform-postgres-app)
PASSWORD_ENC=$(echo -n "prod-password-789" | kubeseal --raw --from-file=/dev/stdin --namespace data-prod --name platform-postgres-app)

# Update clusters/local/prod/values.yaml
# Then commit and push
```

### Cloud Environments

Same process, but use the appropriate namespace:
- Cloud Dev: `--namespace data-dev`
- Cloud QA: `--namespace data-qa`
- Cloud Prod: `--namespace data-prod`

## Verification

After deployment, verify the secret was created:

```bash
# Check SealedSecret
kubectl get sealedsecret -n data-dev

# Check unsealed Secret
kubectl get secret platform-postgres-app -n data-dev

# View secret data (base64 encoded)
kubectl get secret platform-postgres-app -n data-dev -o yaml

# Decode password
kubectl get secret platform-postgres-app -n data-dev \
  -o jsonpath='{.data.password}' | base64 -d
```

## Updating Secrets

To change a password:

1. **Encrypt new value:**
   ```bash
   echo -n "new-password" | kubeseal --raw \
     --from-file=/dev/stdin \
     --namespace data-dev \
     --name platform-postgres-app
   ```

2. **Update values file** with new encrypted value

3. **Commit and push:**
   ```bash
   git add clusters/local/dev/values.yaml
   git commit -m "Update password for local dev"
   git push
   ```

4. **Argo CD will automatically sync** (if auto-sync is enabled)

5. **Or manually sync:**
   ```bash
   argocd app sync cnpg-cluster-local-dev
   ```

## Rotating Sealed Secrets Controller Certificate

If you need to rotate the sealed-secrets controller certificate:

1. **Backup old certificate** (to decrypt existing secrets if needed)

2. **Re-encrypt all secrets** with new certificate:
   ```bash
   # For each environment, re-run the encryption commands
   # and update the values files
   ```

3. **Update all values files** and commit

4. **Sync all Argo CD Applications**

## Troubleshooting

### Secret Not Created

```bash
# Check SealedSecret exists
kubectl get sealedsecret -n data-dev

# Check sealed-secrets controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets

# Describe SealedSecret for events
kubectl describe sealedsecret platform-postgres-app -n data-dev
```

### Wrong Namespace Error

**Error:** `cannot unseal: no key could decrypt secret`

**Solution:** You encrypted with wrong namespace. Re-encrypt with correct namespace:
```bash
echo -n "value" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace data-dev \  # ← Make sure this matches!
  --name platform-postgres-app
```

### Cluster Can't Start - Secret Not Found

**Error:** Cluster waiting for secret `platform-postgres-app`

**Solution:** 
1. Check SealedSecret was created: `kubectl get sealedsecret -n data-dev`
2. Check Secret was unsealed: `kubectl get secret platform-postgres-app -n data-dev`
3. Check sealed-secrets controller is running: `kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets`

### Values File Not Updated

**Error:** Still shows `REPLACE_WITH_ENCRYPTED_USERNAME`

**Solution:** You forgot to update the values file with actual encrypted values. Run the encryption commands and update the file.

## Security Best Practices

1. **Never commit plain secrets** - Always encrypt first
2. **Use strong passwords** - Especially for production
3. **Different passwords per environment** - Don't reuse passwords
4. **Rotate regularly** - Change passwords periodically
5. **Backup controller certificate** - Store securely for disaster recovery
6. **Limit access to kubeseal** - Only authorized users should encrypt secrets

## Migration from Old Secrets Structure

If you were using the old `secrets/` directories:

1. **Get existing password:**
   ```bash
   kubectl get secret platform-postgres-app -n data-dev \
     -o jsonpath='{.data.password}' | base64 -d
   ```

2. **Encrypt it:**
   ```bash
   echo -n "existing-password" | kubeseal --raw \
     --from-file=/dev/stdin \
     --namespace data-dev \
     --name platform-postgres-app
   ```

3. **Update values file** with encrypted value

4. **Deploy via Argo CD** - The new SealedSecret will replace the old one

5. **Remove old secrets/ directory** (optional, kept for reference)

## Advanced: Using External Secrets

For production environments, consider using External Secrets Operator with:
- AWS Secrets Manager
- Azure Key Vault
- Google Secret Manager
- HashiCorp Vault

This provides additional features like automatic rotation and centralized secret management.

## References

- [Sealed Secrets Documentation](https://github.com/bitnami-labs/sealed-secrets)
- [CloudNativePG Secrets](https://cloudnative-pg.io/documentation/current/bootstrap/#bootstrap-an-empty-cluster-initdb)
- [Argo CD Sealed Secrets](https://argo-cd.readthedocs.io/en/stable/operator-manual/secret-management/)
