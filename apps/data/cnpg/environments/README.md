# Environment-Specific Values

Values de entorno del cluster `platform-postgres`. Se aplican **encima** del `values.yaml` base, en ese orden.

## Structure

```
environments/
└── local/
    └── dev.yaml      # data-dev — el único entorno que existe
```

Hasta la issue #44 había también `local/{qa,prod}.yaml` y `cloud/{dev,qa,prod}.yaml`. Se borraron por dos
motivos que se sostienen por separado:

- **Nunca configuraron nada.** Ponían las claves en `cluster.instances` cuando el subchart espera
  `cluster.cluster.instances` (el primer nivel es la clave del subchart en el wrapper, el segundo es su propia
  sección `cluster`). Helm acepta el fichero, el subchart lo ignora, el Cluster sale con los defaults. Fallo
  silencioso. `local/prod.yaml` además colgaba `monitoring:` de `sealedSecret:`.
- **Los namespaces no existen.** No hay `data-qa` ni `data-prod` en el clúster; los únicos namespaces de datos
  son `data-dev` y `data-casa`.

Si algún día hace falta un entorno nuevo, se copia `local/dev.yaml` — que sí tiene el anidamiento bueno — y se
crea su Application en `argocd/clusters/`.

## Usage

```bash
# Render local
helm template platform-postgres-dev . -f values.yaml -f environments/local/dev.yaml

# Despliegue real (GitOps)
kubectl apply -f apps/data/cnpg/argocd/clusters/local/dev.yaml
```

## Qué lleva `local/dev.yaml`

| Bloque | Contenido |
|---|---|
| `cluster.cluster` | 1 instancia, Longhorn (20Gi + 1Gi WAL), afinidad worker + `performance=high`, tuning de PostgreSQL |
| `cluster.cluster.roles` | role `deal_tracker_prod` (`.spec.managed.roles` del Cluster) |
| `cluster.databases` | base `deal_tracker_prod` (CRD `Database`) — hermana de `cluster.cluster`, no dentro |
| `cluster.backups` | interruptor del backup lógico a MinIO (la forma completa está en el `values.yaml` base) |
| `sealedSecret` | credenciales de la BD `platform` (`platform-postgres-app`) |
| `backupSecret` | credencial S3 del backup (`cnpg-backup-s3-creds`) |
| `roleSecrets` | contraseña del role `deal_tracker_prod` (`deal-tracker-prod-db`, tipo basic-auth) |

Las dos primeras filas nuevas son la trampa de anidamiento de siempre, pero en las dos direcciones:
`roles` va **dentro** de `cluster.cluster` (el subchart lo mete él en el bloque `managed`), y `databases`
va **fuera**, colgando de `cluster` a secas. Escribir `cluster.managed.roles`, que es lo intuitivo, no
falla: renderiza sin el role y nadie se entera. Ver `../README.md`, "Bases de datos y roles".

## Encrypted Secrets

El ciphertext vive aquí mismo, en el values, y es seguro de commitear. El namespace y el nombre **forman parte
del cifrado**: tienen que coincidir con el destino real, y la misma credencial en otro namespace se sella otra
vez.

```bash
echo -n "your-value" | kubeseal --raw --from-file=/dev/stdin \
  --namespace data-dev --name platform-postgres-app \
  --controller-name sealed-secrets --controller-namespace kube-system
```

Ver `docs/SEALED-SECRETS-GUIDE.md`.

## References

- [Main Chart README](../README.md)
- [Sealed Secrets Guide](../../../docs/SEALED-SECRETS-GUIDE.md)
- [Argo CD Applications](../argocd/README.md)
