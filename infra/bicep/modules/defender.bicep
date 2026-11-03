// Microsoft Defender for Cloud plans for the services MatterHub uses:
// container image vulnerability assessment + runtime threat detection, Key Vault
// anomaly detection, and PostgreSQL threat protection.
targetScope = 'subscription'

var plans = [
  'Containers'
  'KeyVaults'
  'OpenSourceRelationalDatabases'
]

@batchSize(1) // pricing updates conflict if run in parallel
resource defenderPlans 'Microsoft.Security/pricings@2026-07-01' = [for plan in plans: {
  name: plan
  properties: {
    pricingTier: 'Standard'
  }
}]
