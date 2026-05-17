# ADR-0006: Kustomize (not Helm) for K8s manifests

- **Status:** Accepted
- **Date:** 2026-05-17

## Context

We need to deploy the same images to a local cluster (Docker Desktop K8s / kind /
minikube) and to a cloud cluster (Civo / Hetzner / EKS) with different secrets,
replica counts, ingress hosts, and storage classes.

Two mainstream choices: Helm charts or Kustomize overlays.

## Decision

Use **Kustomize** with `base/` + `overlays/local/` + `overlays/cloud/`.

## Consequences

**Wins**
- No templating language — manifests are real YAML, fully validated by `kubectl --dry-run`
- Patches are auditable diffs, not Go template logic
- Helm is overkill for a single application that isn't being re-used by other teams

**Costs**
- For multi-environment fan-out beyond ~3 environments, Helm starts paying for itself; we don't expect that
- ArgoCD support is equally good for both
