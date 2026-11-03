# Composition of the MatterHub platform for one environment.
# envs/<env>/ only sets inputs and the state backend; all logic lives here so dev and
# prod are built from exactly the same code.

data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

locals {
  name = "matterhub-${var.environment}"
  tags = merge({
    service             = "matterhub"
    environment         = var.environment
    managed-by          = "terraform"
    data-classification = "OFFICIAL"
    cost-centre         = "digital-data-cyber"
    repository          = "matterhub"
  }, var.extra_tags)

  secrets_officers = compact([
    data.azurerm_client_config.current.object_id, # the pipeline identity
    var.ops_group_object_id,
  ])
}

module "network" {
  source              = "../modules/network"
  name                = local.name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
  address_space       = var.address_space
  subnet_cidrs        = var.subnet_cidrs
  tags                = local.tags
}

module "monitoring" {
  source                = "../modules/monitoring"
  name                  = local.name
  location              = var.location
  resource_group_name   = data.azurerm_resource_group.this.name
  log_retention_days    = var.log_retention_days
  daily_quota_gb        = var.log_daily_quota_gb
  alert_email_addresses = var.alert_email_addresses
  tags                  = local.tags
}

module "acr" {
  source                        = "../modules/acr"
  name                          = local.name
  location                      = var.location
  resource_group_name           = data.azurerm_resource_group.this.name
  sku                           = var.acr_sku
  public_network_access_enabled = !var.private_data_plane
  private_endpoint_subnet_id    = var.acr_sku == "Premium" ? module.network.private_endpoints_subnet_id : null
  private_dns_zone_id           = module.network.private_dns_zone_ids["acr"]
  log_analytics_workspace_id    = module.monitoring.log_analytics_workspace_id
  tags                          = local.tags
}

module "keyvault" {
  source                        = "../modules/keyvault"
  name                          = local.name
  location                      = var.location
  resource_group_name           = data.azurerm_resource_group.this.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  public_network_access_enabled = !var.private_data_plane
  private_endpoint_subnet_id    = module.network.private_endpoints_subnet_id
  private_dns_zone_id           = module.network.private_dns_zone_ids["keyvault"]
  log_analytics_workspace_id    = module.monitoring.log_analytics_workspace_id
  secrets_officer_principal_ids = local.secrets_officers
  tags                          = local.tags
}

module "postgres" {
  source                       = "../modules/postgres"
  name                         = local.name
  location                     = var.location
  resource_group_name          = data.azurerm_resource_group.this.name
  tenant_id                    = data.azurerm_client_config.current.tenant_id
  sku_name                     = var.postgres.sku_name
  storage_mb                   = var.postgres.storage_mb
  high_availability            = var.postgres.high_availability
  backup_retention_days        = var.postgres.backup_retention_days
  geo_redundant_backup_enabled = var.postgres.geo_redundant_backup_enabled
  password_version             = var.postgres.password_version
  delegated_subnet_id          = module.network.postgres_subnet_id
  private_dns_zone_id          = module.network.private_dns_zone_ids["postgres"]
  key_vault_id                 = module.keyvault.id
  key_vault_ready              = module.keyvault.secrets_officer_assignment_ids
  log_analytics_workspace_id   = module.monitoring.log_analytics_workspace_id
  tags                         = local.tags
}

module "aks" {
  source                          = "../modules/aks"
  name                            = local.name
  location                        = var.location
  resource_group_name             = data.azurerm_resource_group.this.name
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  kubernetes_version              = var.aks.kubernetes_version
  sku_tier                        = var.aks.sku_tier
  subnet_id                       = module.network.aks_subnet_id
  system_pool                     = var.aks.system_pool
  user_pool                       = var.aks.user_pool
  admin_group_object_ids          = var.aks_admin_group_object_ids
  private_cluster_enabled         = var.aks.private_cluster_enabled
  api_server_authorized_ip_ranges = var.aks.authorized_ip_ranges
  defender_enabled                = var.aks.defender_enabled
  deployment_safeguards_level     = var.aks.deployment_safeguards_level
  deployer_principal_ids          = [data.azurerm_client_config.current.object_id]
  log_analytics_workspace_id      = module.monitoring.log_analytics_workspace_id
  monitor_workspace_id            = module.monitoring.monitor_workspace_id
  tags                            = local.tags
}

# Nodes pull images from ACR with their kubelet identity: no image pull secrets.
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = module.acr.id
  role_definition_name = "AcrPull"
  principal_id         = module.aks.kubelet_object_id
}

module "workload_identity" {
  source              = "../modules/workload-identity"
  name                = local.name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
  oidc_issuer_url     = module.aks.oidc_issuer_url
  key_vault_id        = module.keyvault.id
  tags                = local.tags
}

module "alerts" {
  source               = "../modules/alerts"
  name                 = local.name
  location             = var.location
  resource_group_name  = data.azurerm_resource_group.this.name
  action_group_id      = module.monitoring.action_group_id
  monitor_workspace_id = module.monitoring.monitor_workspace_id
  aks_cluster_id       = module.aks.id
  aks_cluster_name     = module.aks.name
  postgres_server_id   = module.postgres.id
  key_vault_id         = module.keyvault.id
  tags                 = local.tags
}
