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

## Los dos flags de `--controller-*` no son opcionales aqui

Todos los ejemplos de este documento llevan:

```
--controller-name sealed-secrets --controller-namespace kube-system
```

**No los quites.** `kubeseal` necesita la clave publica del controller y, para encontrarla, busca
por defecto un Service llamado `sealed-secrets-controller` en `kube-system`. En este cluster el
Service se llama **`sealed-secrets`** —lo instalo el chart de Bitnami con ese nombre de release—,
asi que sin los flags el comando falla antes de cifrar nada:

```
error: cannot get sealed secret service: services "sealed-secrets-controller" not found
```

Es un fallo limpio y ruidoso, no silencioso: no produce un ciphertext malo, simplemente no
produce ninguno. Pero cuesta un rato entenderlo si la documentacion enseña el comando sin ellos.

La alternativa, si vas a sellar muchos valores seguidos, es traerte el certificado una vez y
pasarlo con `--cert`, que no consulta al controller:

```bash
kubeseal --fetch-cert \
  --controller-name sealed-secrets --controller-namespace kube-system > pub-cert.pem
# a partir de aqui: kubeseal --raw --cert pub-cert.pem ...
```

`scripts/seal-authentik.sh` los tiene en dos variables (`SEALED_SECRETS_CONTROLLER_NAME` y
`SEALED_SECRETS_CONTROLLER_NAMESPACE`) por si algun dia cambian.

## Comprobar un sellado ANTES de desplegarlo

Un ciphertext sellado contra el namespace equivocado es indistinguible de uno bueno a simple
vista, y el fallo aparece tarde: el SealedSecret se aplica sin quejarse y lo que no llega nunca
es el `Secret`. El controlador sabe decir si puede descifrarlo, y `kubeseal --validate` se lo
pregunta sin desplegar nada:

```bash
# Los dos SealedSecret del Keycloak de produccion
helm template keycloak-prod apps/security/keycloak --namespace security-prod \
  -f apps/security/keycloak/values.yaml \
  -f apps/security/keycloak/environments/local/prod.yaml \
  -s templates/sealedsecret.yaml -s templates/realm-smtp-sealedsecret.yaml \
| kubeseal --validate --controller-name sealed-secrets --controller-namespace kube-system

# Los tres de su base de datos (el cluster general de produccion)
helm template platform-postgres-prod apps/data/platform-postgres --namespace data-prod \
  -f apps/data/platform-postgres/values.yaml \
  -f apps/data/platform-postgres/environments/local/prod.yaml \
  -s templates/sealedsecret.yaml -s templates/backup-s3-sealedsecret.yaml \
  -s templates/role-sealedsecret.yaml \
| kubeseal --validate --controller-name sealed-secrets --controller-namespace kube-system
```

Silencio significa valido. Si no, dice `error: unable to decrypt sealed secret: <nombre>`.

Hay **tres formas de que esto falle en falso**, y las tres dan un error que apunta al
ciphertext en vez de a lo que pasa:

1. **Sin `-s`, no vale.** kubeseal manda por el cable lo que le llegue, y el render completo
   lleva StatefulSets y ConfigMaps que el endpoint de validacion no acepta. El error es
   distinto y no habla de descifrar:
   `cannot validate sealed secret: an error on the server ("") has prevented the request`.
   Con `-s` se rinden solo las plantillas pedidas; varios `-s` en el mismo comando valen, y
   varios SealedSecret en el mismo flujo tambien.
2. **Sin `--namespace` en el `helm template`, tampoco.** `.Release.Namespace` renderiza
   `default`, los SealedSecret salen con `namespace: default` y el controlador **falla al
   validarlos TODOS** — incluidos los que llevan meses funcionando en el cluster. Si algo
   falla la validacion, mira primero el `namespace:` del manifiesto renderizado.
3. **Re-serializar el manifiesto por el camino** (un `yaml.safe_dump` de python, por ejemplo):
   plegar un base64 largo a 80 columnas lo corrompe, y el error que sale es el mismo.

Comprobado en este cluster el 22/08/2026, con las dos caras: los sellados buenos validan y el
mismo chart renderizado sin `--namespace` falla.

## Quitar una clave de un SealedSecret no la quita del cluster

Borrar una entrada de `encryptedData` en el values, commitear y sincronizar **puede no borrar
nada**. El objeto vivo se queda con la clave, y el `Secret` desellado tambien.

Pasado el 22/08/2026 al retirar de `security-dev` la clave SMTP de produccion (issue #62): Argo
sincronizo `Succeeded`, el ConfigMap y el CronJob perdieron la referencia, y la credencial siguio
ahi tan tranquila.

**Por que.** Server-side apply solo borra los campos que **el propio aplicador** poseia. Si otro
field manager reclama esa clave, sobrevive:

```bash
kubectl -n <ns> get sealedsecret <nombre> --show-managed-fields -o json \
| python3 -c "
import json,sys
for m in json.load(sys.stdin)['metadata'].get('managedFields',[]):
    print(m['manager'], m['operation'])"
```

Lo que salio:

```
argocd-controller          Apply     <- ya no reclama la clave: la quito bien
kubectl-client-side-apply  Update    <- la sigue reclamando. Este es el problema
```

Ese `kubectl-client-side-apply` es el rastro de los syncs que corrieron **sin** `ServerSideApply`,
que durante mucho tiempo fueron todos los manuales: la operacion lanzada con `{"sync":{}}` perdia
esa opcion en silencio (ver el comentario `syncPolicy` de cualquier Application manual). O sea que
este sintoma es una **secuela** de aquel, y aparece justo cuando por fin se borra un campo.

**El arreglo:** borrar el objeto y dejar que Argo lo recree, para que nazca con un solo dueño.

```bash
kubectl -n <ns> delete sealedsecret <nombre>
kubectl -n argocd patch app <app> --type merge \
  -p '{"operation":{"sync":{"syncOptions":["CreateNamespace=true","ServerSideApply=true"]}}}'
```

El `Secret` desellado cuelga del `SealedSecret` por `ownerReference`, asi que se va y vuelve con el.
**Comprueba antes que nadie lo este consumiendo en ese momento** —un Job a medias se queda sin
credenciales— y despues, que los gestores son solo `argocd-controller` y `controller`.

**Como saber si hay mas objetos asi**, que es lo que de verdad interesa: los que tienen los DOS
gestores a la vez. Con esto salio uno solo en cinco namespaces, porque es el unico sitio donde se
habia llegado a borrar un campo:

```bash
kubectl -n <ns> get <tipo> --show-managed-fields -o json \
| python3 -c "
import json,sys
for o in json.load(sys.stdin).get('items',[]):
    ms=[m['manager'] for m in o['metadata'].get('managedFields',[])]
    if any('client-side-apply' in m for m in ms) and any('argocd' in m for m in ms):
        print(o['kind'], o['metadata']['name'])"
```

## Encrypting Secrets

### Step 1: Encrypt Your Values

For each environment, you need to encrypt the username and password:

```bash
# Encrypt username for local dev
echo -n "platform" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace data-dev \
  --name platform-postgres-app \
  --controller-name sealed-secrets --controller-namespace kube-system

# Output: AgAxxxxxxxxxxxxxxxxxxxxx...

# Encrypt password for local dev
echo -n "your-strong-password" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace data-dev \
  --name platform-postgres-app \
  --controller-name sealed-secrets --controller-namespace kube-system

# Output: AgByyyyyyyyyyyyyyyyyyyyyy...
```

**Important Notes:**
- Use the correct `--namespace` for each environment (data-dev, data-qa, data-prod)
- The `--name` must match the secret name: `platform-postgres-app`
- The `-n` flag in `echo` is critical (no newline)

### Step 2: Update Values File

Edit the environment's values file with the encrypted values:

```yaml
# apps/data/cnpg/environments/local/dev.yaml
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
USERNAME_ENC=$(echo -n "platform" | kubeseal --raw --from-file=/dev/stdin --namespace data-dev --name platform-postgres-app \
  --controller-name sealed-secrets --controller-namespace kube-system)
PASSWORD_ENC=$(echo -n "dev-password-123" | kubeseal --raw --from-file=/dev/stdin --namespace data-dev --name platform-postgres-app \
  --controller-name sealed-secrets --controller-namespace kube-system)

# Update apps/data/cnpg/environments/local/dev.yaml
# Then commit and push
```

> **Los tres bloques de abajo son plantillas de sintaxis, no un inventario.** `data-qa` no
> existe (sus values se borraron en la #44) y `data-prod` existe desde la #62 pero contiene
> **solo** `keycloak-postgres-prod`: ahi no hay ningun `platform-postgres-app` que sellar.
> Mira que namespaces hay de verdad antes de copiar uno.

### Local QA (data-qa namespace)

```bash
# Encrypt secrets
USERNAME_ENC=$(echo -n "platform" | kubeseal --raw --from-file=/dev/stdin --namespace data-qa --name platform-postgres-app \
  --controller-name sealed-secrets --controller-namespace kube-system)
PASSWORD_ENC=$(echo -n "qa-password-456" | kubeseal --raw --from-file=/dev/stdin --namespace data-qa --name platform-postgres-app \
  --controller-name sealed-secrets --controller-namespace kube-system)

# Update clusters/local/qa/values.yaml
# Then commit and push
```

### Local Prod (data-prod namespace)

```bash
# Encrypt secrets
USERNAME_ENC=$(echo -n "platform" | kubeseal --raw --from-file=/dev/stdin --namespace data-prod --name platform-postgres-app \
  --controller-name sealed-secrets --controller-namespace kube-system)
PASSWORD_ENC=$(echo -n "prod-password-789" | kubeseal --raw --from-file=/dev/stdin --namespace data-prod --name platform-postgres-app \
  --controller-name sealed-secrets --controller-namespace kube-system)

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
     --name platform-postgres-app \
     --controller-name sealed-secrets --controller-namespace kube-system
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
# El --namespace tiene que ser EXACTAMENTE el del despliegue: forma parte del cifrado.
echo -n "value" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace data-dev \
  --name platform-postgres-app \
  --controller-name sealed-secrets --controller-namespace kube-system
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
     --name platform-postgres-app \
     --controller-name sealed-secrets --controller-namespace kube-system
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
