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

variable "tenant_id" {
  type = string
}

variable "public_network_access_enabled" {
  description = "Prod: false (private endpoint only; Terraform runs on a self-hosted agent in the VNet)."
  type        = bool
  default     = true
}

variable "private_endpoint_subnet_id" {
  type = string
}

variable "private_dns_zone_id" {
  type = string
}

variable "log_analytics_workspace_id" {
  type = string
}

variable "secrets_officer_principal_ids" {
  description = "Principals allowed to write secrets (the deployment identity, the ops group)."
  type        = list(string)
  default     = []
}
