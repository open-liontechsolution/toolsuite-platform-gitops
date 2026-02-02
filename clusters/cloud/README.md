# Cloud Overlay (Scaffold)

This overlay is a placeholder for cloud-specific settings. Typical changes include:

- Setting a cloud storage class (e.g., `gp3`, `pd-ssd`).
- Increasing CPU/memory requests and limits.
- Adjusting backup retention and schedules.
- Adding tolerations or node affinities for dedicated database node pools.

Update `clusters/cloud/kustomization.yaml` with patches once cloud requirements are defined.
