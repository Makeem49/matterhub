# Platform metric alerts (Azure Monitor) and an activity-log alert for risky
# control-plane operations. Application SLO alerts are in prometheus_rules.tf;
# log-search alerts are deployed from the ARM template in infra/arm/.

resource "azurerm_monitor_metric_alert" "aks_node_cpu" {
  name                = "alert-${var.name}-aks-node-cpu"
  resource_group_name = var.resource_group_name
  scopes              = [var.aks_cluster_id]
  description         = "Average node CPU above 80% for 15 minutes: capacity or a runaway workload."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_cpu_usage_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = var.action_group_id
  }
}

resource "azurerm_monitor_metric_alert" "postgres_cpu" {
  name                = "alert-${var.name}-psql-cpu"
  resource_group_name = var.resource_group_name
  scopes              = [var.postgres_server_id]
  description         = "PostgreSQL CPU above 80% for 15 minutes."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = var.action_group_id
  }
}

resource "azurerm_monitor_metric_alert" "postgres_storage" {
  name                = "alert-${var.name}-psql-storage"
  resource_group_name = var.resource_group_name
  scopes              = [var.postgres_server_id]
  description         = "PostgreSQL storage above 85% (auto-grow is on, but check growth trend and cost)."
  severity            = 2
  frequency           = "PT15M"
  window_size         = "PT30M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "storage_percent"
    aggregation      = "Maximum"
    operator         = "GreaterThan"
    threshold        = 85
  }

  action {
    action_group_id = var.action_group_id
  }
}

resource "azurerm_monitor_metric_alert" "postgres_connections_failed" {
  name                = "alert-${var.name}-psql-conn-failed"
  resource_group_name = var.resource_group_name
  scopes              = [var.postgres_server_id]
  description         = "Failed PostgreSQL connections: wrong/rotated password, firewall or exhaustion."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "connections_failed"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }

  action {
    action_group_id = var.action_group_id
  }
}

resource "azurerm_monitor_metric_alert" "key_vault_availability" {
  name                = "alert-${var.name}-kv-availability"
  resource_group_name = var.resource_group_name
  scopes              = [var.key_vault_id]
  description         = "Key Vault availability dropped: secret mounts and rotation will fail."
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.KeyVault/vaults"
    metric_name      = "Availability"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 99
  }

  action {
    action_group_id = var.action_group_id
  }
}

# Security: tell the team whenever someone grants access in this resource group.
resource "azurerm_monitor_activity_log_alert" "role_assignment_write" {
  name                = "alert-${var.name}-role-assignment"
  location            = "global"
  resource_group_name = var.resource_group_name
  scopes              = ["/subscriptions/${split("/", var.aks_cluster_id)[2]}/resourceGroups/${var.resource_group_name}"]
  description         = "A role assignment was created in the MatterHub resource group."
  tags                = var.tags

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.Authorization/roleAssignments/write"
  }

  action {
    action_group_id = var.action_group_id
  }
}
