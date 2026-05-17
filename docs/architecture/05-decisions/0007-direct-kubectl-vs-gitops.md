# ADR-0007: Support both direct kubectl deploy and GitOps via ArgoCD

- **Status:** Accepted
- **Date:** 2026-05-17

## Context

The release workflow needs to deploy versioned images to a K8s cluster. Two
common shapes:

- **Direct kubectl** — Action authenticates to cluster, runs `kustomize | kubectl apply`
- **GitOps via ArgoCD** — Action updates manifest image tags, commits; ArgoCD syncs

For a portfolio project that needs to be cheap to demo *and* show production-grade thinking, both paths matter.

## Decision

`release.yml` supports both modes via a workflow input (`deploy_mode`):
`direct-kubectl` (default) or `gitops-argocd`. Both reuse the same Kustomize
manifests; only the deploy mechanism differs.

## Consequences

**Wins**
- Portfolio demo can use direct kubectl (no separate ArgoCD setup needed)
- Real production demonstrations can use GitOps (the kind of thing enterprise EHS shops run)
- Switching is a workflow-input change, not a structural refactor

**Costs**
- Two code paths in `release.yml` — kept minimal; one is just a manifest commit
