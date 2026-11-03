environment         = "prod"
location            = "uksouth"
resource_group_name = "rg-matterhub-prod"

address_space = ["10.30.0.0/16"]
subnet_cidrs = {
  aks               = "10.30.0.0/22"
  postgres          = "10.30.4.0/24"
  private_endpoints = "10.30.5.0/24"
}

aks = {
  sku_tier                = "Standard"
  private_cluster_enabled = true # deployments run on self-hosted agents in the VNet
  system_pool             = { vm_size = "Standard_D4ds_v5", min_count = 3, max_count = 5 }
  user_pool               = { vm_size = "Standard_D4ds_v5", min_count = 3, max_count = 9 }
  defender_enabled        = true
  # Block non-compliant workloads in prod; dev only warns so engineers can experiment.
  deployment_safeguards_level = "Enforcement"
}

acr_sku            = "Premium"
private_data_plane = true

postgres = {
  sku_name                     = "GP_Standard_D2ds_v5"
  storage_mb                   = 65536
  high_availability            = true # zone-redundant standby, automatic failover
  backup_retention_days        = 35
  geo_redundant_backup_enabled = true # restore into UK West if UK South is lost
}

log_retention_days    = 90
log_daily_quota_gb    = -1
alert_email_addresses = ["matterhub-oncall@example.gov.uk"]
