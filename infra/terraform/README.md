# Terraform: workload infrastructure

```text
modules/            single-purpose modules (network, aks, acr, keyvault, postgres, monitoring, workload-identity, alerts)
stack/              composition: wires the modules together for one environment
envs/dev|prod/      provider + backend + tfvars only, calling ../../stack
```

Dev and prod are built from the same `stack`; they differ only in `terraform.tfvars`.

## Use

```bash
cd infra/terraform/envs/dev
az login                                   # or ARM_* env vars + ARM_USE_OIDC in CI
export ARM_SUBSCRIPTION_ID=<subscription>
terraform init -backend-config=backend.hcl
terraform plan -out tfplan
terraform apply tfplan
terraform output -json platform | jq .     # values the deployment pipeline consumes
```

Requirements: Terraform **>= 1.11** (write-only arguments and ephemeral resources),
azurerm provider **5.x**, the Bicep foundation deployed (resource groups and state storage).

Commit the provider lock file for every platform the team uses:

```bash
terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=windows_amd64
```

## Notable design points

- **No secret in state**: the PostgreSQL password is an `ephemeral "random_password"`
  passed to `administrator_password_wo` and Key Vault `value_wo`. Bump
  `postgres.password_version` to rotate.
- **Least-privilege pipeline**: the deploy identity gets `AKS Cluster User` plus
  `AKS RBAC Admin` on the `matterhub` namespace only.
- **Safe defaults with prod overrides**: private cluster, Premium ACR, private data plane,
  zone-redundant HA, geo-redundant backups and Deployment Safeguards in *Enforcement* are
  all switched on in `envs/prod/terraform.tfvars`.
- **Lifecycle guards**: `prevent_destroy` on the database; `ignore_changes` for node counts
  (owned by the autoscaler) and PostgreSQL zones (swapped by HA failover).
