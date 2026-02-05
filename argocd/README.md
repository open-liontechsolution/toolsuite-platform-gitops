# Argo CD Application Manifests

This directory contains Argo CD Application manifests for deploying CloudNativePG components using Helm charts.

## Structure

```
argocd/
├── operator/
│   └── cnpg-operator.yaml          # CNPG operator (deploy once per cluster)
└── clusters/
    ├── local/                       # Local k3s environments
    │   ├── cnpg-cluster-dev.yaml
    │   ├── cnpg-cluster-qa.yaml
    │   └── cnpg-cluster-prod.yaml
    └── cloud/                       # Cloud environments
        ├── cnpg-cluster-dev.yaml
        ├── cnpg-cluster-qa.yaml
        └── cnpg-cluster-prod.yaml
```

## Prerequisites

1. Argo CD installed in your cluster
2. Repository added to Argo CD
3. Secrets created in target namespaces (see environment READMEs)

## Deployment Order

### 1. Deploy the Operator (Once per Cluster)

```bash
# Update the repoURL in operator/cnpg-operator.yaml
# Replace <your-org> with your GitHub organization

kubectl apply -f argocd/operator/cnpg-operator.yaml
```

Wait for the operator to be healthy:

```bash
# Check Argo CD Application
kubectl get application -n argocd cnpg-operator

# Check operator pods
kubectl get pods -n cnpg-system
```

### 2. Create Secrets for Each Environment

Before deploying clusters, create sealed secrets:

```bash
# Example for local dev
cd clusters/local/dev
cp secrets/secret-app.example.yaml secrets/secret-app.yaml
# Edit and set password
kubeseal --format=yaml --namespace data-dev \
  < secrets/secret-app.yaml \
  > secrets/sealedsecret-app.yaml
kubectl apply -f secrets/sealedsecret-app.yaml
rm secrets/secret-app.yaml
```

Repeat for each environment you want to deploy.

### 3. Deploy PostgreSQL Clusters

Deploy clusters for your chosen environments:

```bash
# Update repoURL in the Application manifests
# Replace <your-org> with your GitHub organization

# Local dev
kubectl apply -f argocd/clusters/local/cnpg-cluster-dev.yaml

# Local QA
kubectl apply -f argocd/clusters/local/cnpg-cluster-qa.yaml

# Local prod (manual sync)
kubectl apply -f argocd/clusters/local/cnpg-cluster-prod.yaml

# Cloud environments
kubectl apply -f argocd/clusters/cloud/cnpg-cluster-dev.yaml
kubectl apply -f argocd/clusters/cloud/cnpg-cluster-qa.yaml
kubectl apply -f argocd/clusters/cloud/cnpg-cluster-prod.yaml
```

## Configuration

### Update Repository URL

Before applying, update the `repoURL` in all manifests:

```bash
# Replace <your-org> with your GitHub organization
sed -i 's|<your-org>|your-github-org|g' argocd/**/*.yaml
```

Or manually edit each file:

```yaml
source:
  repoURL: https://github.com/your-org/toolsuite-platform-gitops
```

### Sync Policies

#### Automated Sync (Dev/QA)

Development and QA environments use automated sync:

```yaml
syncPolicy:
  automated:
    prune: true        # Remove resources not in Git
    selfHeal: true     # Auto-sync on drift
    allowEmpty: false  # Prevent empty syncs
```

#### Manual Sync (Production)

Production environments require manual approval:

```yaml
syncPolicy:
  # No automated section - requires manual sync
  syncOptions:
    - CreateNamespace=true
```

To sync production manually:

```bash
# Via kubectl
kubectl patch application cnpg-cluster-local-prod -n argocd \
  --type merge -p '{"operation":{"sync":{}}}'

# Via Argo CD CLI
argocd app sync cnpg-cluster-local-prod

# Via UI
# Navigate to the Application and click "Sync"
```

## Verification

### Check Argo CD Applications

```bash
# List all applications
kubectl get applications -n argocd

# Check specific application
kubectl get application cnpg-cluster-local-dev -n argocd

# Describe for details
kubectl describe application cnpg-cluster-local-dev -n argocd
```

### Check Application Status via Argo CD CLI

```bash
# Install Argo CD CLI first
# https://argo-cd.readthedocs.io/en/stable/cli_installation/

# List applications
argocd app list

# Get application details
argocd app get cnpg-cluster-local-dev

# View sync status
argocd app sync-status cnpg-cluster-local-dev
```

### Check Deployed Resources

```bash
# Check operator
kubectl get pods -n cnpg-system

# Check cluster (example: dev)
kubectl get cluster -n data-dev
kubectl cnpg status platform-postgres -n data-dev
kubectl get pods -n data-dev
kubectl get svc -n data-dev
```

## Troubleshooting

### Application OutOfSync

If an application shows as OutOfSync:

```bash
# View diff
argocd app diff cnpg-cluster-local-dev

# Force sync
argocd app sync cnpg-cluster-local-dev --force

# Or via kubectl
kubectl patch application cnpg-cluster-local-dev -n argocd \
  --type merge -p '{"operation":{"sync":{"syncStrategy":{"hook":{},"apply":{"force":true}}}}}'
```

### Application Degraded

Check the application status:

```bash
kubectl describe application cnpg-cluster-local-dev -n argocd

# Check operator logs
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg

# Check cluster status
kubectl describe cluster platform-postgres -n data-dev
```

### Helm Chart Not Found

Ensure Helm dependencies are committed:

```bash
cd apps/platform/cnpg-operator
helm dependency update
git add charts/
git commit -m "Add Helm dependencies"
git push
```

### Secret Not Found

Ensure the secret exists before syncing:

```bash
kubectl get secret platform-postgres-app -n data-dev
```

If missing, create and apply the sealed secret as described above.

## Advanced Configuration

### Using Argo CD Projects

For better organization, create an Argo CD Project:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: data-platform
  namespace: argocd
spec:
  description: Data platform components
  sourceRepos:
    - https://github.com/your-org/toolsuite-platform-gitops
  destinations:
    - namespace: 'cnpg-system'
      server: https://kubernetes.default.svc
    - namespace: 'data-*'
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
```

Then update Applications to use this project:

```yaml
spec:
  project: data-platform
```

### Using ApplicationSets

For managing multiple environments, consider using ApplicationSets:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cnpg-clusters-local
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - env: dev
            namespace: data-dev
            valuesFile: values-local-dev.yaml
          - env: qa
            namespace: data-qa
            valuesFile: values-local-qa.yaml
          - env: prod
            namespace: data-prod
            valuesFile: values-local-prod.yaml
  template:
    metadata:
      name: 'cnpg-cluster-local-{{env}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/your-org/toolsuite-platform-gitops
        path: apps/data/cnpg
        targetRevision: main
        helm:
          releaseName: 'platform-postgres-{{env}}'
          valueFiles:
            - values.yaml
            - '{{valuesFile}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{namespace}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

### Health Checks

Argo CD automatically monitors CNPG Cluster health. Custom health checks are defined in the Applications:

```yaml
ignoreDifferences:
  - group: postgresql.cnpg.io
    kind: Cluster
    jsonPointers:
      - /spec/instances
      - /status
```

This prevents false OutOfSync states due to CNPG's internal status updates.

## References

- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [Argo CD Helm Support](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/)
- [CloudNativePG Documentation](https://cloudnative-pg.io/)
- [CloudNativePG Helm Charts](https://github.com/cloudnative-pg/charts)
