# Instrucciones para Generar SealedSecrets

## Valores a Encriptar para Dev

Usa los siguientes valores plaintext para generar el SealedSecret consolidado:

### Valores de Referencia (secret-app-*.yaml)

```yaml
KEYCLOAK_ADMIN: admin
KEYCLOAK_ADMIN_PASSWORD: 7NuP8%k&VaGgZSDdyBFy
KC_DB: postgres
KC_DB_USERNAME: keycloak_dev
KC_DB_PASSWORD: adNcA4t^Q@tJVa80a2zY
KC_DB_URL_HOST: platform-postgres-dev-rw.data-dev.svc.cluster.local
KC_DB_URL_PORT: "5432"
KC_DB_URL_DATABASE: keycloak_dev
```

## Comandos para Generar el SealedSecret

### 1. Crear el Secret Temporal

```bash
kubectl create secret generic keycloak-credentials \
  --from-literal=KEYCLOAK_ADMIN=admin \
  --from-literal=KEYCLOAK_ADMIN_PASSWORD='7NuP8%k&VaGgZSDdyBFy' \
  --from-literal=KC_DB=postgres \
  --from-literal=KC_DB_USERNAME=keycloak_dev \
  --from-literal=KC_DB_PASSWORD='adNcA4t^Q@tJVa80a2zY' \
  --from-literal=KC_DB_URL_HOST=platform-postgres-dev-rw.data-dev.svc.cluster.local \
  --from-literal=KC_DB_URL_PORT=5432 \
  --from-literal=KC_DB_URL_DATABASE=keycloak_dev \
  --namespace=security-dev \
  --dry-run=client -o yaml > /tmp/keycloak-credentials-plain.yaml
```

### 2. Encriptar con Kubeseal

```bash
kubeseal --format=yaml \
  --namespace=security-dev \
  < /tmp/keycloak-credentials-plain.yaml \
  > sealedsecret-keycloak-credentials.yaml
```

### 3. Extraer los Valores Encriptados

Abre el archivo `sealedsecret-keycloak-credentials.yaml` y copia los valores encriptados de la sección `spec.encryptedData`.

### 4. Actualizar dev.yaml

Reemplaza los placeholders en `environments/local/dev.yaml` con los valores encriptados:

```yaml
sealedSecret:
  enabled: true
  name: keycloak-credentials
  encryptedData:
    KEYCLOAK_ADMIN: "<valor-encriptado>"
    KEYCLOAK_ADMIN_PASSWORD: "<valor-encriptado>"
    KC_DB: "<valor-encriptado>"
    KC_DB_USERNAME: "<valor-encriptado>"
    KC_DB_PASSWORD: "<valor-encriptado>"
    KC_DB_URL_HOST: "<valor-encriptado>"
    KC_DB_URL_PORT: "<valor-encriptado>"
    KC_DB_URL_DATABASE: "<valor-encriptado>"
```

## Notas

- El secret se llama ahora `keycloak-credentials` (consolidado)
- Todos los valores se inyectan como variables de entorno en el pod de Keycloak
- Los valores plaintext están en los archivos `secret-app-*.yaml` para referencia
- Después de actualizar dev.yaml, puedes eliminar los archivos plaintext por seguridad
