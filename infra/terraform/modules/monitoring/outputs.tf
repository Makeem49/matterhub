output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.this.id
}

output "log_analytics_workspace_guid" {
  description = "Workspace (customer) ID, used by `az monitor log-analytics query -w`."
  value       = azurerm_log_analytics_workspace.this.workspace_id
}

output "application_insights_connection_string" {
  value     = azurerm_application_insights.this.connection_string
  sensitive = true
}

output "monitor_workspace_id" {
  value = azurerm_monitor_workspace.this.id
}

output "action_group_id" {
  value = azurerm_monitor_action_group.this.id
}
