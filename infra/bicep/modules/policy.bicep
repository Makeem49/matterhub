// Guard-rails enforced by Azure Policy at subscription scope. Built-in definitions are
// referenced by ID; their display names are in the comments.
targetScope = 'subscription'

param allowedLocations array
param requiredTags array

// "Allowed locations"
var allowedLocationsDefinition = '/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c'
// "Require a tag on resource groups"
var requireRgTagDefinition = '/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025'
// "Kubernetes cluster pod security baseline standards for Linux-based workloads" (initiative)
var aksPodSecurityBaseline = '/providers/Microsoft.Authorization/policySetDefinitions/a8640138-9b0a-4a28-b8cb-1666c838647d'

resource allowedLocationsAssignment 'Microsoft.Authorization/policyAssignments@2025-03-01' = {
  name: 'matterhub-allowed-locations'
  properties: {
    displayName: 'MatterHub: resources must be in UK regions'
    description: 'Data residency: OFFICIAL data stays in UK South / UK West.'
    policyDefinitionId: allowedLocationsDefinition
    enforcementMode: 'Default'
    parameters: {
      listOfAllowedLocations: {
        value: allowedLocations
      }
    }
    nonComplianceMessages: [
      {
        message: 'MatterHub resources must be deployed to uksouth or ukwest.'
      }
    ]
  }
}

resource requiredTagAssignments 'Microsoft.Authorization/policyAssignments@2025-03-01' = [for tag in requiredTags: {
  name: 'matterhub-require-rg-tag-${tag}'
  properties: {
    displayName: 'MatterHub: resource groups must have a "${tag}" tag'
    policyDefinitionId: requireRgTagDefinition
    enforcementMode: 'Default'
    parameters: {
      tagName: {
        value: tag
      }
    }
  }
}]

resource aksBaselineAssignment 'Microsoft.Authorization/policyAssignments@2025-03-01' = {
  name: 'matterhub-aks-pod-baseline'
  properties: {
    displayName: 'MatterHub: AKS pod security baseline'
    description: 'Audit privileged containers, host namespaces, hostPath volumes and similar.'
    policyDefinitionId: aksPodSecurityBaseline // initiatives are assigned through policyDefinitionId too
    enforcementMode: 'Default'
    parameters: {
      effect: {
        value: 'audit' // move to "deny" once existing workloads are compliant
      }
    }
  }
}
