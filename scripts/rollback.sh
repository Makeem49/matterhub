#!/usr/bin/env bash
# Roll the MatterHub Helm release back and verify it. See docs/runbooks/rollback.md.
#
#   ./scripts/rollback.sh                 # previous revision
#   ./scripts/rollback.sh 41              # specific revision
#   NAMESPACE=matterhub RELEASE=matterhub ./scripts/rollback.sh
#
# Database migrations are NOT reverted: they are written to be backwards compatible
# (expand/contract), so the previous app version runs against the newer schema.
set -euo pipefail

NAMESPACE="${NAMESPACE:-matterhub}"
RELEASE="${RELEASE:-matterhub}"
TARGET="${1:-}"

echo "Current history:"
helm history "$RELEASE" -n "$NAMESPACE" --max 5

if [[ -z "$TARGET" ]]; then
  # Most recent *deployed or superseded* revision before the current one.
  TARGET="$(helm history "$RELEASE" -n "$NAMESPACE" -o json \
    | jq -r '[.[] | select(.status == "superseded")] | last | .revision')"
  [[ -n "$TARGET" && "$TARGET" != "null" ]] || { echo "No previous revision to roll back to" >&2; exit 1; }
fi

read -r -p "Roll ${RELEASE} in ${NAMESPACE} back to revision ${TARGET}? [y/N] " answer
[[ "${answer,,}" == "y" ]] || { echo "Aborted"; exit 1; }

helm rollback "$RELEASE" "$TARGET" -n "$NAMESPACE" --wait --timeout 5m
kubectl -n "$NAMESPACE" rollout status "deploy/${RELEASE}" --timeout 5m
helm test "$RELEASE" -n "$NAMESPACE" --logs --timeout 3m

image="$(kubectl -n "$NAMESPACE" get deploy "$RELEASE" -o jsonpath='{.spec.template.spec.containers[0].image}')"
echo "Rolled back to revision ${TARGET}; now running ${image}"
echo "Next: record the rollback in the incident log and open a postmortem (docs/postmortem-template.md)."
