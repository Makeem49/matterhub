# Microsoft Entra Workload ID for the MatterHub pods.
# Kubernetes issues a short-lived token for the service account; Entra ID trusts it
# through the federated credential and exchanges it for an Azure access token.
# Nothing secret is stored in the cluster or in the pipeline.

resource "azurerm_user_assigned_identity" "this" {
  name                = "id-${var.name}-workload"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "sa" {
  for_each                  = toset(var.service_accounts)
  name                      = "fic-${var.namespace}-${each.value}"
  user_assigned_identity_id = azurerm_user_assigned_identity.this.id
  issuer                    = var.oidc_issuer_url
  subject                   = "system:serviceaccount:${var.namespace}:${each.value}"
  audience                  = ["api://AzureADTokenExchange"]
}

# Least privilege: read secret values only, on this vault only.
resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}
