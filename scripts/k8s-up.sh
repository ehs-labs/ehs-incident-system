#!/usr/bin/env bash
# ============================================================================
# k8s-up.sh — bring up the full EHS stack on a local Kubernetes cluster
#
# Kind path (recommended):
#   Creates the cluster from k8s/kind-config.yaml if it does not already exist,
#   builds and loads the three application images, then applies the local overlay.
#
# Also supports docker-desktop and minikube; those already expose the local
# Docker daemon to the cluster so no image loading is required.
#
# Idempotent: running it twice on the same cluster is safe.
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
RESET=$'\033[0m'

log()  { printf "${GREEN}==> %s${RESET}\n" "$*"; }
warn() { printf "${YELLOW}!! %s${RESET}\n" "$*"; }
die()  { printf "${RED}ERROR: %s${RESET}\n" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Configurable via environment
# ---------------------------------------------------------------------------
CLUSTER_NAME="${CLUSTER_NAME:-ehs}"
NAMESPACE=ehs
# Compose project name determines the local image name prefix.
# docker compose config --images confirmed: ehs-incident-system-<service>
COMPOSE_PROJECT=ehs-incident-system

# ---------------------------------------------------------------------------
# Tool checks
# ---------------------------------------------------------------------------
check_tools() {
  command -v kubectl   >/dev/null || die "kubectl is required (https://kubernetes.io/docs/tasks/tools/)"
  command -v kustomize >/dev/null || die "kustomize is required (https://kustomize.io)"
  command -v docker    >/dev/null || die "docker is required (https://docs.docker.com/get-docker/)"
}

# ---------------------------------------------------------------------------
# Kind helpers
# ---------------------------------------------------------------------------
kind_cluster_exists() {
  kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"
}

ensure_kind() {
  command -v kind >/dev/null || die "kind is required for this path (brew install kind)"

  if kind_cluster_exists; then
    log "Kind cluster '${CLUSTER_NAME}' already exists."
  else
    log "Creating kind cluster '${CLUSTER_NAME}' from k8s/kind-config.yaml..."
    kind create cluster --name "$CLUSTER_NAME" --config k8s/kind-config.yaml
  fi

  # Switch to the kind context.
  kubectl config use-context "kind-${CLUSTER_NAME}"
}

# ---------------------------------------------------------------------------
# Image build, tag, and load for kind
# ---------------------------------------------------------------------------
build_and_load_images() {
  log "Building application images via docker compose..."
  docker compose build core-api notifier frontend

  # Map: compose image name -> overlay image name
  local services=("core-api" "notifier" "frontend")
  local compose_names=(
    "${COMPOSE_PROJECT}-core-api"
    "${COMPOSE_PROJECT}-notifier"
    "${COMPOSE_PROJECT}-frontend"
  )
  local registry_names=(
    "ghcr.io/ehs-labs/ehs-core-api:dev"
    "ghcr.io/ehs-labs/ehs-notifier:dev"
    "ghcr.io/ehs-labs/ehs-frontend:dev"
  )

  for i in "${!services[@]}"; do
    local compose_img="${compose_names[$i]}"
    local registry_img="${registry_names[$i]}"

    log "Tagging ${compose_img} -> ${registry_img}"
    docker tag "$compose_img" "$registry_img"

    log "Loading ${registry_img} into kind cluster '${CLUSTER_NAME}'..."
    kind load docker-image "$registry_img" --name "$CLUSTER_NAME"
  done
}

# ---------------------------------------------------------------------------
# Apply overlay and wait for the stack to come up
# ---------------------------------------------------------------------------
apply_and_wait() {
  log "Applying k8s/overlays/local via Kustomize..."
  kustomize build k8s/overlays/local | kubectl apply -f -

  log "Waiting for migration jobs..."
  kubectl -n "$NAMESPACE" wait --for=condition=Complete job/db-migrate-core-api --timeout=5m \
    || warn "db-migrate-core-api not yet complete — check: kubectl -n ${NAMESPACE} logs job/db-migrate-core-api"
  kubectl -n "$NAMESPACE" wait --for=condition=Complete job/db-migrate-notifier --timeout=5m \
    || warn "db-migrate-notifier not yet complete — check: kubectl -n ${NAMESPACE} logs job/db-migrate-notifier"

  log "Waiting for deployment rollouts..."
  kubectl -n "$NAMESPACE" rollout status deployment/core-api  --timeout=5m
  kubectl -n "$NAMESPACE" rollout status deployment/notifier  --timeout=5m
  kubectl -n "$NAMESPACE" rollout status deployment/frontend  --timeout=5m
}

print_instructions() {
  local host_entry="127.0.0.1   app.ehs.local"

  cat <<EOF

${GREEN}Stack is up.${RESET}

  Add to /etc/hosts (if not already present):
    ${host_entry}

  Kind path — reach the app via nginx-ingress on host port 8080:
    http://app.ehs.local:8080

  Or port-forward directly (useful for debugging):
    kubectl -n ${NAMESPACE} port-forward svc/frontend 5173:80
    kubectl -n ${NAMESPACE} port-forward svc/core-api 3000:3000
    kubectl -n ${NAMESPACE} port-forward svc/notifier 4000:4000

  Tear down:
    kind delete cluster --name ${CLUSTER_NAME}

EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
check_tools

CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
log "Active kubectl context: ${CONTEXT:-<none>}"

case "$CONTEXT" in
  "kind-${CLUSTER_NAME}")
    # Already on the right kind cluster — still rebuild and reload images so
    # the cluster picks up any local code changes.
    log "Resuming on existing kind cluster: ${CONTEXT}"
    build_and_load_images
    ;;

  kind-*)
    # A different kind cluster is active; switch to ours or create it.
    log "Different kind cluster active ('${CONTEXT}'). Switching to '${CLUSTER_NAME}'..."
    ensure_kind
    build_and_load_images
    ;;

  "")
    # No context at all — create the kind cluster.
    log "No active kubectl context. Creating kind cluster '${CLUSTER_NAME}'..."
    ensure_kind
    build_and_load_images
    ;;

  docker-desktop)
    log "Using Docker Desktop's built-in Kubernetes."
    log "Skipping kind image load — Docker Desktop shares the local daemon."
    log "Building application images via docker compose..."
    docker compose build core-api notifier frontend
    # Tag to match the overlay image names, no kind load needed.
    docker tag "${COMPOSE_PROJECT}-core-api" "ghcr.io/ehs-labs/ehs-core-api:dev"
    docker tag "${COMPOSE_PROJECT}-notifier"  "ghcr.io/ehs-labs/ehs-notifier:dev"
    docker tag "${COMPOSE_PROJECT}-frontend"  "ghcr.io/ehs-labs/ehs-frontend:dev"
    ;;

  minikube)
    log "Using minikube."
    log "Building images into minikube's Docker daemon..."
    # Build directly inside minikube's Docker daemon so no explicit image push
    # is needed.  eval sets DOCKER_HOST etc. for the duration of this script.
    eval "$(minikube docker-env)"
    docker compose build core-api notifier frontend
    docker tag "${COMPOSE_PROJECT}-core-api" "ghcr.io/ehs-labs/ehs-core-api:dev"
    docker tag "${COMPOSE_PROJECT}-notifier"  "ghcr.io/ehs-labs/ehs-notifier:dev"
    docker tag "${COMPOSE_PROJECT}-frontend"  "ghcr.io/ehs-labs/ehs-frontend:dev"
    ;;

  *)
    warn "Unrecognized context '${CONTEXT}'. Proceeding as a plain kubectl context (no image load)."
    read -rp "Continue? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || exit 1
    ;;
esac

apply_and_wait
print_instructions
