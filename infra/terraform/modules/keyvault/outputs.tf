output "id" {
  value = azurerm_key_vault.this.id
}

output "name" {
  value = azurerm_key_vault.this.name
}

output "vault_uri" {
  value = azurerm_key_vault.this.vault_uri
}

output "secrets_officer_assignment_ids" {
  description = "Lets dependants wait until the deployer can write secrets."
  value       = [for ra in azurerm_role_assignment.secrets_officer : ra.id]
}
