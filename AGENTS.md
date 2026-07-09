# Repository Guidelines

## Project Structure & Module Organization

This is a GitOps repository for Kubernetes platform components. The source of truth is declarative Helm and Argo CD configuration.

- `apps/platform/*`: cluster-level operators and infrastructure such as `cnpg-operator`, `cert-manager`, `internal-ca`, and `longhorn`.
- `apps/data/*`: data services, including CloudNativePG clusters and related PostgreSQL charts.
- `apps/security/*`: identity and security services such as Keycloak and Authentik.
- Each component is a Helm wrapper chart with `Chart.yaml`, `values.yaml`, optional `templates/`, environment values in `environments/`, and Argo CD Applications in `argocd/`.
- `docs/`: deployment, troubleshooting, migration, and Sealed Secrets guides.
- `scripts/`: helper scripts and example environment files for secret sealing.

## Build, Test, and Development Commands

There is no application build step. Validate changes by rendering and linting Helm charts.

```bash
helm dependency build apps/data/cnpg
helm template platform-postgres-dev apps/data/cnpg \
  -f apps/data/cnpg/values.yaml \
  -f apps/data/cnpg/environments/local/dev.yaml
helm lint apps/data/cnpg \
  -f apps/data/cnpg/values.yaml \
  -f apps/data/cnpg/environments/local/dev.yaml
kubectl apply -f apps/data/cnpg/argocd/clusters/local/dev.yaml
```

Use `helm dependency build` before rendering charts with upstream dependencies. Do not commit `Chart.lock` or `charts/`; they are ignored build artifacts.

## Coding Style & Naming Conventions

Use two-space indentation for YAML. Keep values files structured by component, and place upstream chart settings under the dependency key used by that chart. Name environment files by target and tier, for example `environments/local/dev.yaml` or `environments/cloud/prod.yaml`. Preserve existing Argo CD `metadata.name`, Helm `releaseName`, namespaces, and `ignoreDifferences` unless the live deployment is intentionally being renamed.

## Testing Guidelines

For every chart or values change, run `helm lint` and `helm template` with the affected base and environment values. For Argo CD changes, inspect the rendered `Application` and, when cluster access is available, apply or sync in a non-production environment first. There is no unit test framework or coverage target.

## Commit & Pull Request Guidelines

Git history uses Conventional Commit style, for example `feat(authentik): add family user natalia` and `fix(authentik): enable mfa_support on LDAP provider`. Keep commits scoped to one component or behavior. Pull requests should describe the changed chart/environment, include validation commands run, link related issues, and call out any deployment order, secret, or namespace impact.

## Security & Configuration Tips

Never commit plaintext secrets. Commit only Sealed Secrets ciphertext in values files, and ensure the `kubeseal` namespace and secret name exactly match the target deployment. Keep plaintext helper inputs out of Git; `scripts/*-secrets.env` is ignored, while `*.env.example` files may be committed.
