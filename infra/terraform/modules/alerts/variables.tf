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

variable "action_group_id" {
  type = string
}

variable "monitor_workspace_id" {
  type = string
}

variable "aks_cluster_id" {
  type = string
}

variable "aks_cluster_name" {
  type = string
}

variable "postgres_server_id" {
  type = string
}

variable "key_vault_id" {
  type = string
}

variable "slo_availability_target" {
  description = "Fraction of API requests that must succeed (see docs/slo.md)."
  type        = number
  default     = 0.995
}

variable "runbook_base_url" {
  description = "Where runbooks are published, linked from every alert."
  type        = string
  default     = "https://github.com/your-org/matterhub/blob/main/docs/runbooks"
}
