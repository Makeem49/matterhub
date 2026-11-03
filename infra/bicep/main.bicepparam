using 'main.bicep'

param location = 'uksouth'
param environments = [
  'dev'
  'prod'
]
param stateStorageAccountName = 'stmatterhubtfstate'
// Object ID of the GitHub Actions / Azure DevOps workload identity (see docs/pipeline-identity.md).
param deployerPrincipalId = readEnvironmentVariable('DEPLOYER_PRINCIPAL_ID', '00000000-0000-0000-0000-000000000000')
param monthlyBudget = 1500
param budgetContactEmails = [
  'matterhub-platform@example.gov.uk'
]
param enableDefender = true
