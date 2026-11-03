variable "name" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "tenant_id" {
  type = string
}

variable "postgres_version" {
  type    = string
  default = "17"
}

variable "sku_name" {
  description = "B_Standard_B1ms (dev) / GP_Standard_D2ds_v5 (prod)."
  type        = string
}

variable "storage_mb" {
  type    = number
  default = 32768
}

variable "zone" {
  type    = string
  default = "1"
}

variable "high_availability" {
  description = "Zone-redundant HA: a synchronous standby in another zone with automatic failover."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "geo_redundant_backup_enabled" {
  description = "Copy backups to the paired region (UK West) so the database can be restored if UK South is lost."
  type        = bool
  default     = false
}

variable "delegated_subnet_id" {
  type = string
}

variable "private_dns_zone_id" {
  type = string
}

variable "administrator_login" {
  type    = string
  default = "matterhub"
}

variable "password_version" {
  description = "Increment to rotate the administrator password (write-only: never stored in state)."
  type        = number
  default     = 1
}

variable "key_vault_id" {
  description = "Where the generated password is stored for the application."
  type        = string
}

variable "key_vault_secret_name" {
  type    = string
  default = "matterhub-db-password"
}

variable "key_vault_ready" {
  description = "IDs that must exist before writing to Key Vault (deployer role assignments)."
  type        = list(string)
  default     = []
}

variable "log_analytics_workspace_id" {
  type = string
}

variable "database_name" {
  type    = string
  default = "matterhub"
}
