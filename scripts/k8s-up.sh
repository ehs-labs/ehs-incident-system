#!/usr/bin/env bash
# ============================================================================
# k8s-up.sh — bring up the local K8s stack using the local/ Kustomize overlay
#
# Detects the active kubectl context and adapts:
#   - docker-desktop   → uses Docker Desktop's K8s (no extra setup)
#   - kind-*           → uses an existing kind cluster (or creates one)
#   - minikube         → uses an existing minikube cluster
#   - other            → asks the user to confirm
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

command -v kubectl   >/dev/null || die "kubectl is required"
command -v kustomize >/dev/null || die "kustomize is required (https://kustomize.io)"

CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
log "Active kubectl context: ${CONTEXT:-<none>}"

case "$CONTEXT" in
  docker-desktop)
    log "Using Docker Desktop's built-in Kubernetes." ;;
  kind-*)
    log "Using kind cluster: $CONTEXT" ;;
  minikube)
    log "Using minikube cluster." ;;
  "")
    die "No active kubectl context. Enable Kubernetes in Docker Desktop or create a kind/minikube cluster."
    ;;
  *)
    warn "Unrecognized context '$CONTEXT'. Continuing — make sure this is a *local* cluster, not production."
    read -rp "Continue? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || exit 1
    ;;
esac

log "Applying namespace + base resources via Kustomize..."
kustomize build k8s/overlays/local | kubectl apply -f -

log "Waiting for migration jobs..."
kubectl -n ehs wait --for=condition=Complete job/db-migrate-core-api --timeout=5m || warn "Migration job not yet complete"
kubectl -n ehs wait --for=condition=Complete job/db-migrate-notifier --timeout=5m || warn "Migration job not yet complete"

log "Waiting for deployments to roll out..."
kubectl -n ehs rollout status deployment/core-api --timeout=5m
kubectl -n ehs rollout status deployment/notifier --timeout=5m
kubectl -n ehs rollout status deployment/frontend --timeout=5m

cat <<EOF

${GREEN}✓ Local K8s stack is up.${RESET}

  Add to /etc/hosts:
    127.0.0.1   app.ehs.local

  Then open: http://app.ehs.local

  Or port-forward:
    kubectl -n ehs port-forward svc/frontend 5173:80
    kubectl -n ehs port-forward svc/core-api 3000:3000
    kubectl -n ehs port-forward svc/notifier 4000:4000

  Tear down:  ${YELLOW}kustomize build k8s/overlays/local | kubectl delete -f -${RESET}
EOF
