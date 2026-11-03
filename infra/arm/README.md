# ARM templates

`log-alerts/azuredeploy.json` defines Log Analytics (KQL) alert rules
(`Microsoft.Insights/scheduledQueryRules`):

| Rule | Fires when |
|---|---|
| `api-5xx` | > 20 server errors in 5 minutes, split by route (works even if metric scraping is broken) |
| `auth-failures` | spike in rejected tokens / access denied: credential stuffing or a misconfigured client |
| `retention-missing` | no successful retention job in 26 hours |
| `keyvault-denied` | any 403 on the MatterHub Key Vault |

Parameters per environment are in `azuredeploy.parameters.<env>.json`; the workspace and
action group IDs are injected from Terraform outputs by the pipelines.

```bash
az deployment group validate -g rg-matterhub-dev -f log-alerts/azuredeploy.json \
  -p @log-alerts/azuredeploy.parameters.dev.json -p workspaceResourceId=... actionGroupId=...
az deployment group what-if  -g rg-matterhub-dev -f log-alerts/azuredeploy.json -p ...
az deployment group create   -g rg-matterhub-dev -f log-alerts/azuredeploy.json -p ...
```

Azure DevOps deploys it with `AzureResourceManagerTemplateDeployment@3`
(`azure-pipelines/templates/stage-terraform.yml`); GitHub Actions with
`az deployment group create` (`.github/actions/terraform-apply`).

Bicep and ARM share one engine: `az bicep build` turns `infra/bicep/main.bicep` into ARM
JSON, and `az bicep decompile` turns ARM exported from the portal into Bicep.
