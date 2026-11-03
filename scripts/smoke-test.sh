#!/usr/bin/env bash
# Post-deployment smoke test. Proves the expected build is serving and the basic
# security posture holds. Used by both pipelines after `helm upgrade`.
#
#   ./scripts/smoke-test.sh https://matterhub-dev.example.com <git-sha>
#   EXPECT_AUTH=false ./scripts/smoke-test.sh http://localhost:8000 local
set -euo pipefail

BASE_URL="${1:?usage: smoke-test.sh <base-url> <expected-git-sha>}"
EXPECTED_SHA="${2:?usage: smoke-test.sh <base-url> <expected-git-sha>}"
EXPECT_AUTH="${EXPECT_AUTH:-true}"
ATTEMPTS="${ATTEMPTS:-30}"

log() { printf '[smoke] %s\n' "$*"; }
fail() { printf '[smoke] FAIL: %s\n' "$*" >&2; exit 1; }

# 1. The new version is live (old pods may still answer for a few seconds after a rollout).
for attempt in $(seq 1 "$ATTEMPTS"); do
  body="$(curl -fsS --max-time 5 "${BASE_URL}/version" || true)"
  sha="$(jq -r '.git_sha // empty' <<<"${body:-{\}}" 2>/dev/null || true)"
  if [[ "$sha" == "$EXPECTED_SHA" ]]; then
    log "version OK: $(jq -c . <<<"$body")"
    break
  fi
  log "attempt ${attempt}/${ATTEMPTS}: serving '${sha:-nothing}', want '${EXPECTED_SHA}'"
  [[ "$attempt" -eq "$ATTEMPTS" ]] && fail "expected build ${EXPECTED_SHA} never became live"
  sleep 5
done

# 2. Security headers are present on API responses.
headers="$(curl -sS -o /dev/null -D - --max-time 5 "${BASE_URL}/version")"
for h in "x-content-type-options: nosniff" "x-frame-options: deny" "strict-transport-security"; do
  grep -qi "^${h}" <<<"$headers" || fail "missing security header: ${h}"
done
log "security headers OK"

# 3. The API refuses anonymous callers (auth is on in every deployed environment).
status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "${BASE_URL}/api/v1/matters")"
if [[ "$EXPECT_AUTH" == "true" ]]; then
  [[ "$status" == "401" ]] || fail "anonymous request returned ${status}, expected 401"
  log "anonymous access correctly rejected (401)"
else
  [[ "$status" == "200" ]] || fail "API returned ${status}, expected 200 with auth disabled"
  log "API reachable (auth disabled locally)"
fi

# 4. Internal endpoints are not exposed through the ingress.
if [[ "$EXPECT_AUTH" == "true" ]]; then
  status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "${BASE_URL}/metrics")"
  [[ "$status" == "404" ]] || fail "/metrics is publicly reachable (HTTP ${status})"
  log "/metrics not exposed publicly"
fi

log "all checks passed"
