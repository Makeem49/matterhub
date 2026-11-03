#!/usr/bin/env bash
# Run the whole Kubernetes deployment locally on kind (Kubernetes in Docker):
# same Helm chart as AKS, with values-local.yaml instead of Azure services.
#
#   ./scripts/kind-up.sh       # create cluster, build, deploy, smoke test
#   ./scripts/kind-down.sh     # delete it
set -euo pipefail

CLUSTER="${CLUSTER:-matterhub}"
NAMESPACE="matterhub"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for tool in docker kind kubectl helm jq; do
  command -v "$tool" > /dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done

if ! kind get clusters | grep -qx "$CLUSTER"; then
  kind create cluster --name "$CLUSTER" --config "${ROOT}/deploy/local/kind-config.yaml" --wait 120s
fi
kubectl config use-context "kind-${CLUSTER}"

echo "==> Building image"
docker build -t matterhub:local --build-arg GIT_SHA=local "${ROOT}/app"
kind load docker-image matterhub:local --name "$CLUSTER"

echo "==> Namespace (Pod Security 'restricted'), quota and limits"
kubectl apply -f "${ROOT}/deploy/cluster/namespace.yaml"

echo "==> Database password secret (random, local only)"
if ! kubectl -n "$NAMESPACE" get secret matterhub-db > /dev/null 2>&1; then
  kubectl -n "$NAMESPACE" create secret generic matterhub-db \
    --from-literal=database-password="$(openssl rand -base64 24)"
fi

echo "==> PostgreSQL"
kubectl apply -f "${ROOT}/deploy/local/postgres.yaml"
kubectl -n "$NAMESPACE" rollout status statefulset/postgres --timeout 180s

echo "==> MatterHub (Helm)"
helm upgrade --install matterhub "${ROOT}/deploy/helm/matterhub" \
  --namespace "$NAMESPACE" \
  -f "${ROOT}/deploy/helm/matterhub/values-local.yaml" \
  --atomic --wait --timeout 5m
helm test matterhub -n "$NAMESPACE" --logs

echo "==> Smoke test through a port-forward"
kubectl -n "$NAMESPACE" port-forward svc/matterhub 8000:80 > /dev/null 2>&1 &
pf=$!
trap 'kill $pf 2> /dev/null || true' EXIT
sleep 3
EXPECT_AUTH=false "${ROOT}/scripts/smoke-test.sh" http://localhost:8000 local

cat <<MSG

MatterHub is running on kind.
  kubectl -n ${NAMESPACE} port-forward svc/matterhub 8000:80
  open http://localhost:8000/docs
Practise operations:
  kubectl -n ${NAMESPACE} create job --from=cronjob/matterhub-retention retention-now
  kubectl -n ${NAMESPACE} delete pod -l app.kubernetes.io/component=api   # self-healing
  kubectl drain matterhub-worker --ignore-daemonsets --delete-emptydir-data # PDB in action
MSG
