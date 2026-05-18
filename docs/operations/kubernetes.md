# Kubernetes deployment

## Kind from scratch (recommended local path)

[kind](https://kind.sigs.k8s.io/) (Kubernetes IN Docker) runs a full cluster inside local
Docker containers. It is the recommended local path because it is self-contained: no
Docker Desktop Kubernetes toggle, no separate minikube VM, and it produces the same
overlay and image pull behaviour as a remote cluster.

### Prerequisites

```bash
brew install kind kubectl kustomize
# docker must already be running (Docker Desktop or OrbStack)
```

### One-liner

```bash
./scripts/k8s-up.sh
```

What the script does:

- Creates the kind cluster `ehs` from `k8s/kind-config.yaml` if it does not already exist.
- Builds `core-api`, `notifier`, and `frontend` via `docker compose build`, tags each image
  as `ghcr.io/ehs-labs/ehs-<name>:dev`, and loads it into the cluster with `kind load docker-image`.
- Applies `k8s/overlays/local` via Kustomize and waits for the migration jobs and deployment
  rollouts to complete.

After the script finishes, add to `/etc/hosts` (if not already present):

```
127.0.0.1   app.ehs.local
```

Then open `http://app.ehs.local:8080` (nginx-ingress is mapped to host port 8080 by
`k8s/kind-config.yaml`).

### Tear down

```bash
kind delete cluster --name ehs
```

### Troubleshooting

**Image-pull failure (`ErrImagePull` / `ImagePullBackOff`)**

The cluster looks for `ghcr.io/ehs-labs/...:dev` but finds nothing — the image was never
loaded into kind's containerd store.  Fix: re-run `./scripts/k8s-up.sh` (it rebuilds and
reloads).  To verify manually:

```bash
docker images | grep ehs-labs
# If the tag exists locally, load it:
kind load docker-image ghcr.io/ehs-labs/ehs-core-api:dev --name ehs
```

**PVC permission errors on macOS (Postgres / MinIO fail to start)**

Kind nodes are Docker containers; PVC hostPath volumes use the host filesystem with the
container UID.  The Bitnami Postgres image runs as UID 1001; if the PVC directory is
owned by root it will refuse to start.  Workaround: delete the PVC and let the StatefulSet
recreate it, or add an `initContainer` that `chown`s the volume to UID 1001:

```yaml
initContainers:
  - name: fix-perms
    image: busybox
    command: ["sh", "-c", "chown -R 1001:1001 /var/lib/postgresql/data"]
    volumeMounts:
      - name: data
        mountPath: /var/lib/postgresql/data
```

**Karafka SASL boot failure**

The cloud overlay injects `KAFKA_SECURITY_PROTOCOL=SASL_SSL` into the app containers.  The
local overlay does not — Kafka runs plaintext.  If you see `SASL handshake failed`, verify
that `k8s/overlays/local/dev-secrets.yaml` does not accidentally export the cloud-style
SASL env vars (it should not; the cloud patches are only in `k8s/overlays/cloud/`).

**Connection refused on port-forward**

The deployment is not yet ready.  Check pod status and readiness probes:

```bash
kubectl -n ehs get pods
kubectl -n ehs describe pod <pod-name>
```

Wait for all pods to show `Running` and `1/1` before trying to reach the app.

## Local cluster

`./scripts/k8s-up.sh` auto-detects your active kubectl context:

- **kind** (default) — script creates the cluster automatically; see above.
- **Docker Desktop's K8s** — enable in Docker Desktop settings → "Enable Kubernetes".
- **minikube** — `minikube start` then run the script.

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
  ghcr.io/ehs-labs/ehs-core-api=ghcr.io/ehs-labs/ehs-core-api:v0.1.0 \
  ghcr.io/ehs-labs/ehs-notifier=ghcr.io/ehs-labs/ehs-notifier:v0.1.0 \
  ghcr.io/ehs-labs/ehs-frontend=ghcr.io/ehs-labs/ehs-frontend:v0.1.0
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
