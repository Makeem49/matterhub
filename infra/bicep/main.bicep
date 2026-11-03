// MatterHub subscription foundation ("landing zone lite"), deployed with Bicep.
//
// Why Bicep here and Terraform for the workload? These resources must exist BEFORE
// Terraform can run (its state storage) and they are subscription governance owned by the
// platform team (policy, budgets, Defender). Bicep is Azure-native, needs no state file of
// its own, and supports `what-if` previews. See docs/adr/0002-terraform-and-bicep.md.
//
//   az deployment sub what-if --location uksouth -f infra/bicep/main.bicep -p infra/bicep/main.bicepparam
//   az deployment sub create  --location uksouth -f infra/bicep/main.bicep -p infra/bicep/main.bicepparam

targetScope = 'subscription'

@description('Primary region for all resources.')
@allowed([
  'uksouth'
  'ukwest'
])
param location string = 'uksouth'

@description('Environments that get a resource group.')
param environments array = [
  'dev'
  'prod'
]

@description('Globally unique name of the Terraform state storage account.')
@minLength(3)
@maxLength(24)
param stateStorageAccountName string

@description('Object ID of the pipeline identity (federated credential) that runs Terraform.')
param deployerPrincipalId string

@description('Monthly budget for the subscription in GBP.')
@minValue(1)
param monthlyBudget int = 1500

@description('Who receives budget notifications.')
param budgetContactEmails array

@description('Start of the budget period. Must be the first day of a month.')
param budgetStartDate string = '${utcNow('yyyy-MM')}-01'

@description('Enable Microsoft Defender for Cloud plans used by the workload.')
param enableDefender bool = true

@description('Tags applied to every resource group.')
param tags object = {
  service: 'matterhub'
  'managed-by': 'bicep'
  'cost-centre': 'digital-data-cyber'
  'data-classification': 'OFFICIAL'
}

// --------------------------------------------------------------- resource groups

resource workloadRgs 'Microsoft.Resources/resourceGroups@2025-04-01' = [for env in environments: {
  name: 'rg-matterhub-${env}'
  location: location
  tags: union(tags, { environment: env })
}]

resource stateRg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: 'rg-matterhub-tfstate'
  location: location
  tags: union(tags, { environment: 'shared' })
}

// ------------------------------------------------------------------- modules

module stateStorage 'modules/stateStorage.bicep' = {
  name: 'tfstate-storage'
  scope: stateRg
  params: {
    location: location
    storageAccountName: stateStorageAccountName
    deployerPrincipalId: deployerPrincipalId
    tags: union(tags, { environment: 'shared' })
  }
}

module policy 'modules/policy.bicep' = {
  name: 'governance-policy'
  params: {
    allowedLocations: [
      'uksouth'
      'ukwest'
      'global'
    ]
    requiredTags: [
      'service'
      'environment'
    ]
  }
}

module budget 'modules/budget.bicep' = {
  name: 'subscription-budget'
  params: {
    amount: monthlyBudget
    contactEmails: budgetContactEmails
    startDate: budgetStartDate
  }
}

module defender 'modules/defender.bicep' = if (enableDefender) {
  name: 'defender-plans'
}

output workloadResourceGroups array = [for (env, i) in environments: workloadRgs[i].name]
output stateResourceGroup string = stateRg.name
output stateStorageAccount string = stateStorage.outputs.storageAccountName
output stateContainer string = stateStorage.outputs.containerName
