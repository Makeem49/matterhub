locals {
  premium = var.sku == "Premium"
}

resource "azurerm_container_registry" "this" {
  # Registry names are globally unique and alphanumeric only.
  name                          = "acr${replace(var.name, "-", "")}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  sku                           = var.sku
  admin_enabled                 = false # Entra ID auth only (AcrPush / AcrPull roles)
  anonymous_pull_enabled        = false
  public_network_access_enabled = local.premium ? var.public_network_access_enabled : true
  zone_redundancy_enabled       = local.premium
  data_endpoint_enabled         = local.premium
  retention_policy_in_days      = local.premium ? 30 : null # untagged manifests
  tags                          = var.tags
}

resource "azurerm_private_endpoint" "acr" {
  count               = local.premium && var.private_endpoint_subnet_id != null ? 1 : 0
  name                = "pe-${azurerm_container_registry.this.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-acr"
    private_connection_resource_id = azurerm_container_registry.this.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "acr"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

resource "azurerm_monitor_diagnostic_setting" "acr" {
  name                       = "diag-to-log-analytics"
  target_resource_id         = azurerm_container_registry.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }
  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }
}
