variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "location" {
  type    = string
  default = "uksouth"
  validation {
    # Also enforced by Azure Policy (infra/bicep/modules/policy.bicep).
    condition     = contains(["uksouth", "ukwest"], var.location)
    error_message = "MatterHub data must stay in UK regions."
  }
}

variable "resource_group_name" {
  description = "Created by the Bicep foundation deployment (infra/bicep)."
  type        = string
}

variable "address_space" {
  type = list(string)
}

variable "subnet_cidrs" {
  type = object({
    aks               = string
    postgres          = string
    private_endpoints = string
  })
}

variable "aks" {
  type = object({
    kubernetes_version          = optional(string)
    sku_tier                    = string
    private_cluster_enabled     = bool
    authorized_ip_ranges        = optional(list(string), [])
    system_pool                 = object({ vm_size = string, min_count = number, max_count = number })
    user_pool                   = object({ vm_size = string, min_count = number, max_count = number })
    defender_enabled            = bool
    deployment_safeguards_level = optional(string, "Warning")
  })
}

variable "aks_admin_group_object_ids" {
  type    = list(string)
  default = []
}

variable "acr_sku" {
  type    = string
  default = "Standard"
}

variable "private_data_plane" {
  description = "Disable public access to ACR and Key Vault (prod). Pipelines then need self-hosted agents in the VNet."
  type        = bool
  default     = false
}

variable "postgres" {
  type = object({
    sku_name                     = string
    storage_mb                   = optional(number, 32768)
    high_availability            = bool
    backup_retention_days        = number
    geo_redundant_backup_enabled = bool
    password_version             = optional(number, 1)
  })
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "log_daily_quota_gb" {
  type    = number
  default = -1
}

variable "alert_email_addresses" {
  type    = list(string)
  default = []
}

variable "ops_group_object_id" {
  description = "Entra ID group of engineers allowed to manage secrets (break-glass rotation)."
  type        = string
  default     = null
}

variable "extra_tags" {
  type    = map(string)
  default = {}
}
