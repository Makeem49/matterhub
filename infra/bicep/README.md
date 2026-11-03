# Bicep: subscription foundation

Deployed once per subscription by the platform team, before Terraform (which keeps its
state in the storage account created here). See ADR 0002 for the split.

| Module | Creates |
|---|---|
| `main.bicep` | resource groups `rg-matterhub-<env>` and `rg-matterhub-tfstate` |
| `modules/stateStorage.bicep` | GZRS storage for Terraform state: Entra-only (no shared keys), versioning, soft delete, delete lock |
| `modules/policy.bicep` | Azure Policy: UK regions only, required tags on resource groups, AKS pod security baseline |
| `modules/budget.bicep` | monthly budget with 80% actual / 100% forecast alerts |
| `modules/defender.bicep` | Defender for Containers, Key Vault, open-source databases |

```bash
export DEPLOYER_PRINCIPAL_ID=<object id of the pipeline identity>
az bicep lint --file main.bicep
az deployment sub what-if --location uksouth -f main.bicep -p main.bicepparam
az deployment sub create  --location uksouth -f main.bicep -p main.bicepparam
az bicep build --file main.bicep --outfile foundation.json   # the equivalent ARM template
```

`bicepconfig.json` turns the important linter rules into errors so CI fails on them.
