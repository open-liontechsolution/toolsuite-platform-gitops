# Keycloak ArgoCD Applications

This directory contains ArgoCD Application manifests for deploying Keycloak across different environments.

## Structure

```
argocd/
├── clusters/
│   └── local/
│       ├── dev.yaml      # Instancia de dev/QA  -> ns security-dev
│       └── prod.yaml     # Instancia aislada de produccion -> ns security-prod (issue #62)
└── README.md
```

## Deployment

### Prerequisites

1. ArgoCD installed and configured
2. Repository added to ArgoCD
3. `tools` project exists in ArgoCD
4. PostgreSQL databases created in CNPG clusters
5. Sealed Secrets configured in environment overlays

### Deploy to Local Dev

```bash
kubectl apply -f clusters/local/dev.yaml
```

### Deploy to Local Prod

`apps/data/platform-postgres` tiene que estar desplegado antes: esta Application no crea su base.
(Era `apps/data/keycloak-postgres` hasta la #71, que lo renombro al convertirlo en el cluster
general del tier de produccion. Ahora esa base convive alli con `deal_tracker_prod`.)

```bash
kubectl apply -f clusters/local/prod.yaml
```

## Application Configuration

Each Application is configured with:

- **Project**: `tools`
- **Source**: GitHub repository `open-liontechsolution/toolsuite-platform-gitops`
- **Path**: `apps/security/keycloak`
- **Target Revision**: `main`
- **Sync Policy**: **manual, sin `automated`** — las dos. Un auto-sync con prune+selfHeal llevaria
  cualquier error de `realms/` al IdP sin que nadie lo mirase. El razonamiento completo esta en el
  comentario `syncPolicy` de cada fichero.
- **Namespace**: `security-{env}` (auto-created)

## Monitoring

Check application status:

```bash
# List all Keycloak applications
kubectl get applications -n argocd | grep keycloak

# Check specific application
argocd app get keycloak-local-dev

# View sync status
argocd app sync keycloak-local-dev --dry-run
```

## Troubleshooting

### Application Not Syncing

```bash
# Check application details
argocd app get keycloak-local-dev

# View sync errors
argocd app sync keycloak-local-dev

# Force refresh
argocd app refresh keycloak-local-dev --hard
```

### Health Check Failed

```bash
# Check pod status
kubectl get pods -n security-dev

# Check application logs
kubectl logs -n security-dev -l app.kubernetes.io/name=keycloak

# Check events
kubectl get events -n security-dev --sort-by='.lastTimestamp'
```

## References

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Keycloak Deployment Guide](../README.md)
