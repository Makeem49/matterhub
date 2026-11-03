// Terraform remote state. State can contain sensitive values, so:
//  * Entra ID only: shared keys disabled, access via RBAC (Storage Blob Data Contributor)
//  * versioning + soft delete: recover from a corrupted or deleted state file
//  * GZRS: survives a zone or region outage
//  * a CanNotDelete lock on the account

@description('Region.')
param location string

@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Pipeline identity allowed to read and write state.')
param deployerPrincipalId string

param tags object

var storageBlobDataContributor = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
)

resource storage 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_GZRS'
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled' // hosted runners need it; access is still Entra ID + RBAC
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    encryption: {
      keySource: 'Microsoft.Storage'
      requireInfrastructureEncryption: true
      services: {
        blob: {
          enabled: true
        }
      }
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2025-06-01' = {
  parent: storage
  name: 'default'
  properties: {
    isVersioningEnabled: true
    deleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 30
    }
  }
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01' = {
  parent: blobService
  name: 'tfstate'
  properties: {
    publicAccess: 'None'
  }
}

resource deployerAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, deployerPrincipalId, storageBlobDataContributor)
  scope: storage
  properties: {
    principalId: deployerPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: storageBlobDataContributor
  }
}

resource lock 'Microsoft.Authorization/locks@2020-05-01' = {
  name: 'protect-terraform-state'
  scope: storage
  properties: {
    level: 'CanNotDelete'
    notes: 'Terraform state for MatterHub. Deleting it orphans every managed resource.'
  }
}

output storageAccountName string = storage.name
output containerName string = container.name
