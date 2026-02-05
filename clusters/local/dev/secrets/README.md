# Secrets Directory - DEPRECATED

⚠️ **This directory structure is deprecated.**

## New Approach

Secrets are now managed through the Helm chart using SealedSecrets in the values file.

Instead of creating separate secret files here, you should:

1. **Encrypt your secrets** using kubeseal:
   ```bash
   echo -n "platform" | kubeseal --raw \
     --from-file=/dev/stdin \
     --namespace data-dev \
     --name platform-postgres-app
   ```

2. **Add encrypted values** to `clusters/local/dev/values.yaml`:
   ```yaml
   sealedSecret:
     enabled: true
     name: platform-postgres-app
     encryptedData:
       username: "AgA..."  # Your encrypted username
       password: "AgB..."  # Your encrypted password
   ```

3. **Commit to Git** - Encrypted values are safe to commit

4. **Deploy via Argo CD** - The SealedSecret is created automatically with the cluster

## Why This Change?

✅ **Single deployment** - Secrets deployed with cluster, no separate Application needed  
✅ **GitOps-friendly** - Everything in values files  
✅ **Simpler** - One Argo CD Application instead of two  
✅ **Consistent** - Same pattern across all environments  

## Documentation

See `docs/SEALED-SECRETS-GUIDE.md` for complete instructions.

## Legacy Files

The `secret-app.example.yaml` file is kept for reference but is no longer used.
