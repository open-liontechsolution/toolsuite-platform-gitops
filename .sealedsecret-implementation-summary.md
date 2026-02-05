# SealedSecret Template Implementation Summary

**Date:** 2026-02-05  
**Status:** ✅ COMPLETED

## What Was Implemented

Successfully implemented SealedSecret management through Helm chart templates, allowing secrets to be managed via values files and deployed automatically with Argo CD.

## Changes Made

### 1. Created SealedSecret Template ✅

**File:** `apps/data/cnpg/templates/sealedsecret.yaml`

This template creates a SealedSecret resource when enabled in values:

```yaml
{{- if .Values.sealedSecret.enabled }}
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: {{ .Values.sealedSecret.name }}
  namespace: {{ .Release.Namespace }}
spec:
  encryptedData:
    username: {{ .Values.sealedSecret.encryptedData.username | quote }}
    password: {{ .Values.sealedSecret.encryptedData.password | quote }}
{{- end }}
```

### 2. Updated Base Values ✅

**File:** `apps/data/cnpg/values.yaml`

Added sealedSecret configuration structure:

```yaml
sealedSecret:
  enabled: false  # Disabled by default
  name: platform-postgres-app
  encryptedData:
    username: ""
    password: ""
```

### 3. Updated All Environment Values ✅

Added sealedSecret configuration to all 6 environment values files:

- `clusters/local/dev/values.yaml`
- `clusters/local/qa/values.yaml`
- `clusters/local/prod/values.yaml`
- `clusters/cloud/dev/values.yaml`
- `clusters/cloud/qa/values.yaml`
- `clusters/cloud/prod/values.yaml`

Each contains:

```yaml
sealedSecret:
  enabled: true
  name: platform-postgres-app
  encryptedData:
    username: "REPLACE_WITH_ENCRYPTED_USERNAME"
    password: "REPLACE_WITH_ENCRYPTED_PASSWORD"
```

### 4. Created Comprehensive Documentation ✅

**File:** `docs/SEALED-SECRETS-GUIDE.md`

Complete guide covering:
- How the system works
- Prerequisites (sealed-secrets controller, kubeseal CLI)
- Step-by-step encryption instructions
- Environment-specific examples
- Verification steps
- Updating secrets
- Troubleshooting
- Security best practices
- Migration from old approach

### 5. Updated Main Documentation ✅

**File:** `README.md`

Updated sections:
- Secrets Management overview
- Deployment instructions
- Added reference to detailed guide

### 6. Updated Secrets Directories ✅

Added `README.md` to all `secrets/` directories explaining:
- The new approach
- Why the change was made
- How to use the new system
- Reference to detailed documentation

## How It Works Now

### Before (Old Approach)

1. Create secret file in `clusters/{env}/secrets/`
2. Encrypt with kubeseal
3. Apply manually or create separate Argo CD Application
4. Deploy cluster separately

**Problems:**
- Two separate deployments (secrets + cluster)
- More complex Argo CD setup
- Secrets not in values files

### After (New Approach)

1. Encrypt values with kubeseal:
   ```bash
   echo -n "password" | kubeseal --raw \
     --from-file=/dev/stdin \
     --namespace data-dev \
     --name platform-postgres-app
   ```

2. Add to environment's values file:
   ```yaml
   sealedSecret:
     enabled: true
     encryptedData:
       username: "AgA..."
       password: "AgB..."
   ```

3. Commit and push to Git

4. Deploy via Argo CD - **everything in one Application**:
   ```bash
   kubectl apply -f argocd/clusters/local/cnpg-cluster-dev.yaml
   ```

**Benefits:**
✅ Single Argo CD Application per environment  
✅ Secrets deployed automatically with cluster  
✅ Everything in values files (GitOps-friendly)  
✅ Simpler architecture  
✅ Easier to manage  

## Usage Example

### Encrypting Secrets

```bash
# For local dev environment
USERNAME_ENC=$(echo -n "platform" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace data-dev \
  --name platform-postgres-app)

PASSWORD_ENC=$(echo -n "dev-password-123" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace data-dev \
  --name platform-postgres-app)

echo "Username: $USERNAME_ENC"
echo "Password: $PASSWORD_ENC"
```

### Updating Values File

```yaml
# clusters/local/dev/values.yaml
sealedSecret:
  enabled: true
  name: platform-postgres-app
  encryptedData:
    username: "AgABCDEF..."  # Paste encrypted username
    password: "AgAXYZ123..."  # Paste encrypted password
```

### Deploying

```bash
# Via Helm CLI
cd apps/data/cnpg
helm upgrade --install platform-postgres-dev . \
  --namespace data-dev \
  --create-namespace \
  --values values.yaml \
  --values ../../clusters/local/dev/values.yaml

# Via Argo CD (recommended)
kubectl apply -f argocd/clusters/local/cnpg-cluster-dev.yaml
```

### Verification

```bash
# Check SealedSecret was created
kubectl get sealedsecret -n data-dev

# Check Secret was unsealed
kubectl get secret platform-postgres-app -n data-dev

# Check cluster is using the secret
kubectl get cluster platform-postgres -n data-dev -o yaml | grep secretName
```

## Files Created/Modified

### Created
- `apps/data/cnpg/templates/sealedsecret.yaml` - SealedSecret template
- `docs/SEALED-SECRETS-GUIDE.md` - Complete documentation
- `clusters/*/secrets/README.md` (6 files) - Deprecation notices

### Modified
- `apps/data/cnpg/values.yaml` - Added sealedSecret structure
- `clusters/local/dev/values.yaml` - Added sealedSecret config
- `clusters/local/qa/values.yaml` - Added sealedSecret config
- `clusters/local/prod/values.yaml` - Added sealedSecret config
- `clusters/cloud/dev/values.yaml` - Added sealedSecret config
- `clusters/cloud/qa/values.yaml` - Added sealedSecret config
- `clusters/cloud/prod/values.yaml` - Added sealedSecret config
- `README.md` - Updated secrets management section

## Prerequisites

Users must have:

1. **Sealed Secrets Controller** installed in cluster:
   ```bash
   helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
   helm install sealed-secrets sealed-secrets/sealed-secrets \
     --namespace kube-system
   ```

2. **kubeseal CLI** installed locally:
   ```bash
   brew install kubeseal  # macOS
   # or download from GitHub releases
   ```

## Next Steps for Users

1. **Install sealed-secrets controller** if not already installed
2. **Encrypt secrets** for each environment using kubeseal
3. **Update values files** with encrypted values
4. **Commit and push** to Git
5. **Deploy via Argo CD** - secrets will be created automatically

## Migration Path

For existing deployments with old secrets:

1. Get existing password:
   ```bash
   kubectl get secret platform-postgres-app -n data-dev \
     -o jsonpath='{.data.password}' | base64 -d
   ```

2. Encrypt it:
   ```bash
   echo -n "existing-password" | kubeseal --raw \
     --from-file=/dev/stdin \
     --namespace data-dev \
     --name platform-postgres-app
   ```

3. Update values file with encrypted value

4. Redeploy - new SealedSecret will replace old Secret

## Security Notes

- ✅ Encrypted values are safe to commit to Git
- ✅ Only the sealed-secrets controller can decrypt them
- ✅ Each secret is namespace-specific (can't be moved)
- ✅ Each secret is name-specific (can't be renamed)
- ⚠️ Never commit plain text secrets
- ⚠️ Use different passwords per environment
- ⚠️ Rotate passwords regularly

## Troubleshooting

Common issues and solutions documented in `docs/SEALED-SECRETS-GUIDE.md`:

- Secret not created → Check sealed-secrets controller
- Wrong namespace error → Re-encrypt with correct namespace
- Cluster can't start → Verify secret exists
- Values not updated → Check for placeholder values

## Conclusion

The SealedSecret template implementation is complete and ready to use. This provides a cleaner, more GitOps-friendly approach to managing secrets in the CloudNativePG deployment, with everything managed through a single Argo CD Application per environment.

Users need to encrypt their secrets and update the values files before deploying.
