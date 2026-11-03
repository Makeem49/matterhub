# Azure DevOps pipelines

The same delivery model as the GitHub Actions workflows, for teams that use Azure DevOps.

| Pipeline | GitHub Actions equivalent | Does |
|---|---|---|
| `app-pipeline.yml` | `ci.yml` + `cd.yml` | test, scan, build once, deploy dev, approve, promote and deploy prod |
| `infra-pipeline.yml` | `infra.yml` + `foundation.yml` | Bicep foundation, Terraform plan/apply per environment, ARM log alerts |

Reusable templates live in `templates/`:

| Template | Type | Used for |
|---|---|---|
| `steps-python-quality.yml` | steps | lint, mypy, unit + PostgreSQL tests, pip-audit, publish results |
| `steps-container-build.yml` | steps | hadolint, `Docker@2` build/push, Trivy, digest output variable |
| `jobs-helm-deploy.yml` | jobs | `deployment` job: Terraform outputs, `helm upgrade --atomic`, `helm test`, smoke test |
| `stage-terraform.yml` | stages | plan, publish plan artifact, apply that plan in a `deployment` job, then `AzureResourceManagerTemplateDeployment@3` |

## One-off setup

1. **Service connections** (Project settings > Service connections > Azure Resource Manager >
   *Workload identity federation*). No client secrets, so nothing expires or leaks.

   | Name | Scope | Roles |
   |---|---|---|
   | `sc-matterhub-platform` | subscription | Contributor + Resource Policy Contributor + User Access Administrator (conditioned) |
   | `sc-matterhub-dev` | `rg-matterhub-dev` | Contributor, Role Based Access Control Administrator (conditioned), Storage Blob Data Contributor on the state account |
   | `sc-matterhub-prod` | `rg-matterhub-prod` | as dev, plus `AcrPull` on the dev registry for image promotion |
   | `sc-acr-matterhub-dev` | Docker Registry connection to the dev ACR | `AcrPush` |

2. **Environments** (Pipelines > Environments) with **Approvals and checks**:

   | Environment | Checks |
   |---|---|
   | `matterhub-dev`, `matterhub-infra-dev` | none (continuous deployment) |
   | `matterhub-prod`, `matterhub-infra-prod` | Approvals (2 people, not the person who triggered the run); Business hours (Mon-Thu 09:00-16:00 UK); **Query Azure Monitor alerts** (no active Sev0/Sev1 alerts on prod); Exclusive lock (one deployment at a time) |
   | `matterhub-foundation` | Approval by the platform team |

3. **Agent pool** `matterhub-prod-mdp`: a [Managed DevOps Pool](https://learn.microsoft.com/azure/devops/managed-devops-pools/)
   injected into the prod VNet. Prod AKS, ACR and Key Vault have no public endpoints, so
   only agents inside the network can deploy to them.

4. **Variable group** `matterhub-common` (no secrets in it):
   `devAcrName`, `prodAcrName`, `apiAudience`, `appHostname_dev`, `appHostname_prod`, `deployerPrincipalId`.

5. **Extension**: Microsoft DevLabs *Terraform* (provides `TerraformInstaller@1`).

6. **Branch policies on `main`**: require a PR, 1+ reviewer, linked work item, successful
   build validation (`app-pipeline` / `infra-pipeline`), comment resolution.
