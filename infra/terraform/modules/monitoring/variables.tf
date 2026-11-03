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

variable "log_retention_days" {
  description = "Log Analytics interactive retention. Longer retention is cheaper via archive tiers."
  type        = number
  default     = 30
}

variable "daily_quota_gb" {
  description = "Daily ingestion cap (cost guard-rail). -1 means unlimited."
  type        = number
  default     = -1
}

variable "alert_email_addresses" {
  description = "Who receives alerts (team distribution list, on-call address)."
  type        = list(string)
  default     = []
}
