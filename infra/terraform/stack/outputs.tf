# Consumed by the deployment pipelines (terraform output -json) to fill Helm values.

output "resource_group_name" {
  value = data.azurerm_resource_group.this.name
}

output "aks_name" {
  value = module.aks.name
}

output "acr_name" {
  value = module.acr.name
}

output "acr_login_server" {
  value = module.acr.login_server
}

output "key_vault_name" {
  value = module.keyvault.name
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "workload_identity_client_id" {
  value = module.workload_identity.client_id
}

output "postgres_fqdn" {
  value = module.postgres.fqdn
}

output "postgres_server_name" {
  value = module.postgres.name
}

output "postgres_administrator_login" {
  value = module.postgres.administrator_login
}

output "postgres_database_name" {
  value = module.postgres.database_name
}

output "postgres_subnet_cidr" {
  value = module.network.postgres_subnet_cidr
}

output "log_analytics_workspace_guid" {
  value = module.monitoring.log_analytics_workspace_guid
}

output "application_insights_connection_string" {
  value     = module.monitoring.application_insights_connection_string
  sensitive = true
}

output "log_analytics_workspace_id" {
  description = "Resource ID, used to scope the ARM log-search alerts."
  value       = module.monitoring.log_analytics_workspace_id
}

output "action_group_id" {
  value = module.monitoring.action_group_id
}
