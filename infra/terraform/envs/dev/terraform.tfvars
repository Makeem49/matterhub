environment         = "dev"
location            = "uksouth"
resource_group_name = "rg-matterhub-dev"

address_space = ["10.20.0.0/16"]
subnet_cidrs = {
  aks               = "10.20.0.0/22"
  postgres          = "10.20.4.0/24"
  private_endpoints = "10.20.5.0/24"
}

aks = {
  sku_tier                = "Free"
  private_cluster_enabled = false
  # Restrict the public API server, e.g. to the office egress IP and runner ranges.
  authorized_ip_ranges = []
  system_pool          = { vm_size = "Standard_D2ds_v5", min_count = 1, max_count = 2 }
  user_pool            = { vm_size = "Standard_D2ds_v5", min_count = 1, max_count = 3 }
  defender_enabled     = false
}

acr_sku            = "Standard"
private_data_plane = false

postgres = {
  sku_name                     = "B_Standard_B1ms"
  high_availability            = false
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
}

log_retention_days    = 30
log_daily_quota_gb    = 2
alert_email_addresses = ["matterhub-dev-alerts@example.gov.uk"]
