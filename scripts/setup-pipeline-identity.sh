#!/usr/bin/env bash
# Create the Entra ID identities that GitHub Actions uses to deploy, with federated
# credentials (OIDC) instead of client secrets. Idempotent: safe to re-run.
#
#   SUBSCRIPTION_ID=... GITHUB_REPO=your-org/matterhub ./scripts/setup-pipeline-identity.sh
#
# Creates, per environment:
#   matterhub-<env>-plan    Reader-level identity used by pull-request plans
#   matterhub-<env>-deploy  Contributor-level identity used by approved applies/deploys
set -euo pipefail

SUBSCRIPTION_ID="${SUBSCRIPTION_ID:?set SUBSCRIPTION_ID}"
GITHUB_REPO="${GITHUB_REPO:?set GITHUB_REPO (owner/name)}"
ENVIRONMENTS="${ENVIRONMENTS:-dev prod}"
STATE_ACCOUNT="${STATE_ACCOUNT:-stmatterhubtfstate}"
STATE_RG="${STATE_RG:-rg-matterhub-tfstate}"

az account set --subscription "$SUBSCRIPTION_ID"
state_scope="$(az storage account show -n "$STATE_ACCOUNT" -g "$STATE_RG" --query id -o tsv)"

ensure_app() {
  local name="$1" app_id
  app_id="$(az ad app list --display-name "$name" --query '[0].appId' -o tsv)"
  if [[ -z "$app_id" ]]; then
    app_id="$(az ad app create --display-name "$name" --query appId -o tsv)"
    az ad sp create --id "$app_id" > /dev/null
  fi
  echo "$app_id"
}

ensure_federated_credential() {
  local app_id="$1" name="$2" subject="$3"
  if ! az ad app federated-credential list --id "$app_id" --query "[?name=='${name}']" -o tsv | grep -q .; then
    az ad app federated-credential create --id "$app_id" --parameters "$(jq -n \
      --arg name "$name" --arg subject "$subject" \
      '{name: $name, issuer: "https://token.actions.githubusercontent.com", subject: $subject, audiences: ["api://AzureADTokenExchange"]}')" > /dev/null
  fi
}

assign() {
  local principal="$1" role="$2" scope="$3"
  az role assignment create --assignee-object-id "$principal" --assignee-principal-type ServicePrincipal \
    --role "$role" --scope "$scope" --only-show-errors > /dev/null
}

for env in $ENVIRONMENTS; do
  rg_scope="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-matterhub-${env}"

  plan_app="$(ensure_app "matterhub-${env}-plan")"
  plan_sp="$(az ad sp show --id "$plan_app" --query id -o tsv)"
  ensure_federated_credential "$plan_app" "github-${env}-plan" "repo:${GITHUB_REPO}:environment:${env}-plan"
  assign "$plan_sp" "Reader" "$rg_scope"
  assign "$plan_sp" "Key Vault Reader" "$rg_scope"
  assign "$plan_sp" "Storage Blob Data Reader" "$state_scope"

  deploy_app="$(ensure_app "matterhub-${env}-deploy")"
  deploy_sp="$(az ad sp show --id "$deploy_app" --query id -o tsv)"
  ensure_federated_credential "$deploy_app" "github-${env}" "repo:${GITHUB_REPO}:environment:${env}"
  assign "$deploy_sp" "Contributor" "$rg_scope"
  # Needed to create role assignments (AcrPull, Key Vault Secrets User...). In production
  # constrain this with an ABAC condition that limits which roles it may assign.
  assign "$deploy_sp" "Role Based Access Control Administrator" "$rg_scope"
  assign "$deploy_sp" "Storage Blob Data Contributor" "$state_scope"

  echo "${env}: plan client-id=${plan_app}  deploy client-id=${deploy_app}"
  echo "  -> set AZURE_CLIENT_ID in GitHub environments '${env}-plan' and '${env}' respectively"
done
