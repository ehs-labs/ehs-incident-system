# Kubernetes deployment

## Local cluster

`./scripts/k8s-up.sh` auto-detects your active kubectl context:

- **Docker Desktop's K8s** — enable in Docker Desktop settings → "Enable Kubernetes". Already works.
- **kind** — `kind create cluster --name ehs` then run the script
- **minikube** — `minikube start` then run the script

All three apply the same `k8s/overlays/local` overlay.

```bash
./scripts/k8s-up.sh
```

Add to `/etc/hosts`:

```
127.0.0.1   app.ehs.local
```

Open `http://app.ehs.local`.

## Cloud cluster

The `cloud/` overlay assumes:

- A managed Kubernetes cluster (EKS, GKE, AKS, Civo, Hetzner)
- nginx-ingress installed (`helm install ingress-nginx ...`)
- cert-manager installed with a `letsencrypt-prod` ClusterIssuer
- An `External Secrets Operator` (or sealed-secrets) populating the `ehs-secrets` Secret in the `ehs` namespace
- A `StorageClass` providing encrypted PVCs (most managed clouds default to this)

```bash
# Update images in cloud overlay
cd k8s/overlays/cloud
kustomize edit set image \
  ghcr.io/stitch80/ehs-core-api=ghcr.io/stitch80/ehs-core-api:v0.1.0 \
  ghcr.io/stitch80/ehs-notifier=ghcr.io/stitch80/ehs-notifier:v0.1.0 \
  ghcr.io/stitch80/ehs-frontend=ghcr.io/stitch80/ehs-frontend:v0.1.0
cd ../../..

# Apply
kustomize build k8s/overlays/cloud | kubectl apply -f -

# Wait for the migration jobs
kubectl -n ehs wait --for=condition=Complete job/db-migrate-core-api --timeout=10m
kubectl -n ehs wait --for=condition=Complete job/db-migrate-notifier --timeout=10m

# Watch the rollout
kubectl -n ehs rollout status deployment/core-api  --timeout=10m
kubectl -n ehs rollout status deployment/notifier  --timeout=10m
kubectl -n ehs rollout status deployment/frontend  --timeout=10m
```

## Apply order

1. `Namespace`, `ConfigMap`, `Secret`
2. Infra (`Postgres`, `Redis`, `Kafka`, `Karapace`, `MinIO`)
3. Migration `Job`s — block until `Complete`
4. App `Deployment`s
5. `Ingress`, `NetworkPolicy`

The release workflow (`.github/workflows/release.yml`) automates this with two
modes: `direct-kubectl` and `gitops-argocd`. See [ADR-0007](../architecture/05-decisions/0007-direct-kubectl-vs-gitops.md).

## Why Kustomize, not Helm

For a single application (not a re-usable chart for many teams), Kustomize is simpler:
no templating language, no chart releases, just patches over a base. Production-grade and easy to review.
ADR-0006 has the full reasoning.

## Useful commands

```bash
# Quick inspection
kubectl -n ehs get pods
kubectl -n ehs logs deploy/core-api --tail=200 -f
kubectl -n ehs port-forward svc/core-api 3000:3000

# Re-run migration job (idempotent)
kubectl -n ehs delete job db-migrate-core-api
kubectl -n ehs apply -k k8s/overlays/local

# Shell into a running pod
kubectl -n ehs exec -it deploy/core-api -- bash

# Tear down (keeps PVCs by default — add --force --grace-period=0 if needed)
kustomize build k8s/overlays/local | kubectl delete -f -
```
