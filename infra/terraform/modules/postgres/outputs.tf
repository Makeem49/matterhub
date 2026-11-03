output "id" {
  value = azurerm_postgresql_flexible_server.this.id
}

output "name" {
  value = azurerm_postgresql_flexible_server.this.name
}

output "fqdn" {
  value = azurerm_postgresql_flexible_server.this.fqdn
}

output "administrator_login" {
  value = azurerm_postgresql_flexible_server.this.administrator_login
}

output "database_name" {
  value = azurerm_postgresql_flexible_server_database.app.name
}

output "key_vault_secret_name" {
  value = azurerm_key_vault_secret.admin_password.name
}
