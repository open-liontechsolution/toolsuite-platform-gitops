# Troubleshooting Guide

Common issues and solutions for CloudNativePG deployments.

## Table of Contents

- [Argo CD Issues](#argo-cd-issues)
- [Operator Issues](#operator-issues)
- [Cluster Issues](#cluster-issues)
- [Secret Issues](#secret-issues)
- [Storage Issues](#storage-issues)
- [Networking Issues](#networking-issues)

## Argo CD Issues

### Application OutOfSync

**Symptom:** Argo CD shows Application as "OutOfSync"

**Causes:**
- Manual changes made to cluster
- Git changes not yet synced
- Sync policy disabled

**Solutions:**

```bash
# View differences
argocd app diff cnpg-cluster-local-dev

# Manual sync
argocd app sync cnpg-cluster-local-dev

# Force sync (if needed)
argocd app sync cnpg-cluster-local-dev --force
```

### CRD Too Large Error

**Symptom:**
```
CustomResourceDefinition.apiextensions.k8s.io "poolers.postgresql.cnpg.io" is invalid: 
metadata.annotations: Too long: must have at most 262144 bytes
```

**Cause:** CRDs are too large for client-side apply

**Solution:** Ensure Server-Side Apply is enabled in the Application manifest:

```yaml
syncPolicy:
  syncOptions:
    - ServerSideApply=true
    - RespectIgnoreDifferences=true
ignoreDifferences:
  - group: apiextensions.k8s.io
    kind: CustomResourceDefinition
    jsonPointers:
      - /metadata/annotations
```

### Namespace Missing Error

**Symptom:**
```
Namespace for cnpg-controller-manager-config /v1, Kind=ConfigMap is missing
```

**Cause:** Namespace not created or release name not set

**Solution:** Add to Application manifest:

```yaml
helm:
  releaseName: cnpg-operator  # Add this
syncOptions:
  - CreateNamespace=true
```

### Values File Not Found

**Symptom:**
```
failed to load values file: file does not exist
```

**Cause:** Incorrect path to values file

**Solution:** Use relative paths from chart root:

```yaml
helm:
  valueFiles:
    - values.yaml
    - environments/local/dev.yaml  # ✅ Correct
    # NOT: ../../clusters/local/dev/values.yaml  # ❌ Wrong
```

## Operator Issues

### Operator Not Starting

**Symptom:** Operator pod in CrashLoopBackOff or Error state

**Diagnosis:**

```bash
# Check pod status
kubectl get pods -n cnpg-system

# View logs
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg

# Describe pod
kubectl describe pod -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg
```

**Common Causes:**

1. **Insufficient permissions**
   ```bash
   # Check RBAC
   kubectl get clusterrole cloudnative-pg
   kubectl get clusterrolebinding cloudnative-pg
   ```

2. **Webhook issues**
   ```bash
   # Check webhook configuration
   kubectl get validatingwebhookconfigurations
   kubectl get mutatingwebhookconfigurations
   ```

3. **CRDs not installed**
   ```bash
   # Verify CRDs
   kubectl get crd | grep cnpg
   ```

**Solution:** Redeploy operator with correct configuration:

```bash
kubectl delete application cnpg-operator -n argocd
kubectl apply -f apps/platform/cnpg-operator/argocd/operator.yaml
```

### Operator Version Mismatch

**Symptom:** Cluster not reconciling, version warnings in logs

**Solution:** Update operator chart dependency:

```bash
cd apps/platform/cnpg-operator
helm dependency update
git add Chart.lock
git commit -m "Update CNPG operator version"
git push
```

## Cluster Issues

### Cluster Not Starting

**Symptom:** Cluster stuck in "Creating" state

**Diagnosis:**

```bash
# Check cluster status
kubectl get cluster -n data-dev

# Detailed status
kubectl cnpg status platform-postgres -n data-dev

# Check events
kubectl get events -n data-dev --sort-by='.lastTimestamp'

# View cluster details
kubectl describe cluster platform-postgres -n data-dev
```

**Common Causes:**

1. **Operator not running**
   ```bash
   kubectl get pods -n cnpg-system
   ```

2. **Secret not found**
   ```bash
   kubectl get secret platform-postgres-app -n data-dev
   ```

3. **Storage class not available**
   ```bash
   kubectl get storageclass
   ```

4. **Insufficient resources**
   ```bash
   kubectl describe nodes
   ```

### Pod Stuck in Pending

**Symptom:** PostgreSQL pod in Pending state

**Diagnosis:**

```bash
# Check pod status
kubectl get pods -n data-dev

# Describe pod
kubectl describe pod platform-postgres-1 -n data-dev
```

**Common Causes:**

1. **No nodes available**
   - Check node affinity rules
   - Verify node labels

2. **PVC not bound**
   ```bash
   kubectl get pvc -n data-dev
   kubectl describe pvc platform-postgres-1 -n data-dev
   ```

3. **Resource constraints**
   - Insufficient CPU/memory on nodes
   - Check resource requests in values

**Solutions:**

```bash
# Check node resources
kubectl top nodes

# Check PVC
kubectl get pvc -n data-dev

# Adjust resource requests in values file
vim apps/data/cnpg/environments/local/dev.yaml
```

### Cluster Degraded

**Symptom:** Cluster shows as "Degraded" in status

**Diagnosis:**

```bash
# Check cluster status
kubectl cnpg status platform-postgres -n data-dev

# Check pod logs
kubectl logs platform-postgres-1 -n data-dev

# Check replication
kubectl exec -it platform-postgres-1 -n data-dev -- \
  psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

**Common Causes:**
- Replication lag
- Network issues
- Disk space issues

## Secret Issues

### SealedSecret Not Unsealing

**Symptom:** SealedSecret exists but Secret not created

**Diagnosis:**

```bash
# Check SealedSecret
kubectl get sealedsecret -n data-dev

# Check Secret
kubectl get secret platform-postgres-app -n data-dev

# Check sealed-secrets controller logs
kubectl logs -n kube-system -l name=sealed-secrets-controller
```

**Common Causes:**

1. **Wrong namespace**
   - Secret encrypted for different namespace
   - Check namespace in kubeseal command

2. **Wrong secret name**
   - Secret encrypted with different name
   - Check name in kubeseal command

3. **Controller not running**
   ```bash
   kubectl get pods -n kube-system | grep sealed-secrets
   ```

**Solution:** Re-encrypt with correct parameters:

```bash
echo -n "platform" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace data-dev \
  --name platform-postgres-app
```

### Cannot Decrypt Secret

**Symptom:** Error "cannot decrypt secret"

**Cause:** Sealed Secrets controller certificate changed

**Solution:** Re-encrypt all secrets with new certificate:

```bash
# Get new certificate
kubeseal --fetch-cert > pub-cert.pem

# Re-encrypt secrets
echo -n "platform" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace data-dev \
  --name platform-postgres-app \
  --cert pub-cert.pem
```

### Secret Has Wrong Format

**Symptom:** PostgreSQL cannot read credentials

**Cause:** Secret not base64 encoded or has extra characters

**Solution:** Ensure proper encryption:

```bash
# Use -n flag (no newline)
echo -n "your-password" | kubeseal --raw \
  --from-file=/dev/stdin \
  --namespace data-dev \
  --name platform-postgres-app
```

## Storage Issues

### PVC Not Binding

**Symptom:** PVC stuck in Pending state

**Diagnosis:**

```bash
# Check PVC
kubectl get pvc -n data-dev

# Describe PVC
kubectl describe pvc platform-postgres-1 -n data-dev

# Check storage class
kubectl get storageclass
```

**Common Causes:**

1. **Storage class not found**
   ```bash
   # List available storage classes
   kubectl get storageclass
   
   # Update values file with correct class
   vim apps/data/cnpg/environments/local/dev.yaml
   ```

2. **No available storage**
   - Check storage provisioner
   - Verify node has space

3. **Access mode not supported**
   - Check storage class capabilities

**Solution:**

```yaml
# In environment values file
cluster:
  storage:
    storageClass: longhorn  # Use available storage class
    size: 20Gi
```

### Disk Space Full

**Symptom:** PostgreSQL pod crashing, "no space left on device"

**Diagnosis:**

```bash
# Check PVC size
kubectl get pvc -n data-dev

# Check actual usage
kubectl exec -it platform-postgres-1 -n data-dev -- df -h
```

**Solution:** Increase PVC size:

```yaml
# In environment values file
cluster:
  storage:
    size: 50Gi  # Increase size
```

Then apply changes and wait for resize.

## Networking Issues

### Cannot Connect to PostgreSQL

**Symptom:** Connection refused or timeout

**Diagnosis:**

```bash
# Check service
kubectl get svc -n data-dev

# Check endpoints
kubectl get endpoints -n data-dev

# Test from within cluster
kubectl run -it --rm psql \
  --image=postgres:16 \
  --restart=Never \
  --namespace=data-dev \
  -- psql -h platform-postgres-rw -U platform -d app
```

**Common Causes:**

1. **Service not created**
   ```bash
   kubectl get svc -n data-dev
   ```

2. **Pod not ready**
   ```bash
   kubectl get pods -n data-dev
   ```

3. **Network policy blocking**
   ```bash
   kubectl get networkpolicies -n data-dev
   ```

**Solution:** Verify service and pod are running:

```bash
# Check cluster is ready
kubectl cnpg status platform-postgres -n data-dev

# Port forward for testing
kubectl port-forward -n data-dev svc/platform-postgres-rw 5432:5432
```

### Replication Not Working

**Symptom:** Replicas not syncing

**Diagnosis:**

```bash
# Check replication status
kubectl exec -it platform-postgres-1 -n data-dev -- \
  psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Check cluster status
kubectl cnpg status platform-postgres -n data-dev
```

**Common Causes:**
- Network issues between pods
- Replication user permissions
- WAL files missing

## General Troubleshooting Steps

### 1. Check All Components

```bash
# Operator
kubectl get pods -n cnpg-system

# Cluster
kubectl get cluster -n data-dev

# Pods
kubectl get pods -n data-dev

# Services
kubectl get svc -n data-dev

# Secrets
kubectl get secret -n data-dev

# PVCs
kubectl get pvc -n data-dev
```

### 2. Review Logs

```bash
# Operator logs
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg

# Cluster logs
kubectl logs platform-postgres-1 -n data-dev

# Previous logs (if pod restarted)
kubectl logs platform-postgres-1 -n data-dev --previous
```

### 3. Check Events

```bash
# Cluster events
kubectl get events -n data-dev --sort-by='.lastTimestamp'

# Specific resource events
kubectl describe cluster platform-postgres -n data-dev
kubectl describe pod platform-postgres-1 -n data-dev
```

### 4. Verify Configuration

```bash
# Check values being used
helm get values platform-postgres-dev -n data-dev

# Check rendered manifests
helm template platform-postgres-dev apps/data/cnpg \
  --values apps/data/cnpg/values.yaml \
  --values apps/data/cnpg/environments/local/dev.yaml
```

## Getting Help

If you're still stuck:

1. Check [CloudNativePG documentation](https://cloudnative-pg.io/documentation/)
2. Review [Argo CD documentation](https://argo-cd.readthedocs.io/)
3. Check operator logs for specific errors
4. Review cluster events for clues

## Common Error Messages

### "cluster is not ready"

Wait for cluster to initialize. Check:
```bash
kubectl cnpg status platform-postgres -n data-dev
```

### "secret not found"

Ensure SealedSecret was created and unsealed:
```bash
kubectl get sealedsecret -n data-dev
kubectl get secret platform-postgres-app -n data-dev
```

### "storage class not found"

Update values with correct storage class:
```bash
kubectl get storageclass
```

### "insufficient resources"

Check node resources and adjust requests:
```bash
kubectl top nodes
kubectl describe nodes
```

## Prevention Tips

1. **Always encrypt secrets properly** - Use `-n` flag with echo
2. **Use correct namespaces** - Match namespace in kubeseal command
3. **Verify storage class exists** - Check before deploying
4. **Monitor resources** - Ensure nodes have capacity
5. **Test in dev first** - Validate changes in dev environment
6. **Review logs regularly** - Catch issues early
7. **Keep operator updated** - Use latest stable version

## References

- [Deployment Guide](deployment.md)
- [Sealed Secrets Guide](../SEALED-SECRETS-GUIDE.md)
- [CNPG Documentation](https://cloudnative-pg.io/documentation/)
- [Argo CD Troubleshooting](https://argo-cd.readthedocs.io/en/stable/user-guide/troubleshooting/)
