variable "name" {
  description = "Workload name including environment, e.g. matterhub-dev."
  type        = string
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

variable "sku" {
  description = "Standard for dev. Premium for prod (private endpoint, zone redundancy, retention)."
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "sku must be Basic, Standard or Premium."
  }
}

variable "public_network_access_enabled" {
  description = "Disable in prod; images are then pushed from self-hosted agents inside the VNet."
  type        = bool
  default     = true
}

variable "private_endpoint_subnet_id" {
  description = "Subnet for the private endpoint (Premium only). Null to skip."
  type        = string
  default     = null
}

variable "private_dns_zone_id" {
  type    = string
  default = null
}

variable "log_analytics_workspace_id" {
  type = string
}
