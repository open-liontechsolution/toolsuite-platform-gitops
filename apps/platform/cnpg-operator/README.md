# CloudNativePG Operator

This component deploys the CloudNativePG operator. Deploy this **once per cluster**, not per environment.

## Deployment

### Using kubectl + kustomize

```bash
kustomize build apps/platform/cnpg-operator | kubectl apply -f -
```

### Using Argo CD

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cnpg-operator
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<your-org>/toolsuite-platform-gitops
    path: apps/platform/cnpg-operator
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Verification

```bash
kubectl get pods -n cnpg-system
kubectl get crd | grep cnpg
```

## Notes

- The operator creates its own namespace: `cnpg-system`
- This is cluster-wide infrastructure
- Deploy before deploying any PostgreSQL clusters
- All PostgreSQL environments will use this same operator
