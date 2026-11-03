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

variable "kubernetes_version" {
  description = "Minor version, e.g. \"1.33\". Null = AKS default. Patches are applied automatically."
  type        = string
  default     = null
}

variable "sku_tier" {
  description = "Free (dev) or Standard (prod: financially backed API server SLA)."
  type        = string
  default     = "Free"
}

variable "subnet_id" {
  type = string
}

variable "zones" {
  type    = list(string)
  default = ["1", "2", "3"]
}

variable "system_pool" {
  type = object({
    vm_size   = string
    min_count = number
    max_count = number
  })
  default = { vm_size = "Standard_D2ds_v5", min_count = 1, max_count = 3 }
}

variable "user_pool" {
  type = object({
    vm_size   = string
    min_count = number
    max_count = number
  })
  default = { vm_size = "Standard_D4ds_v5", min_count = 1, max_count = 5 }
}

variable "admin_group_object_ids" {
  description = "Entra ID groups that get cluster-admin through Azure RBAC."
  type        = list(string)
  default     = []
}

variable "private_cluster_enabled" {
  description = "Prod: API server reachable only from the VNet (pipelines use self-hosted agents)."
  type        = bool
  default     = false
}

variable "api_server_authorized_ip_ranges" {
  description = "For public clusters, restrict the API server to these CIDRs."
  type        = list(string)
  default     = []
}

variable "log_analytics_workspace_id" {
  type = string
}

variable "monitor_workspace_id" {
  type = string
}

variable "defender_enabled" {
  description = "Microsoft Defender for Containers runtime protection."
  type        = bool
  default     = false
}

variable "container_insights_namespaces" {
  description = "Only collect container logs from these namespaces (cost control)."
  type        = list(string)
  default     = ["matterhub", "kube-system", "app-routing-system"]
}

variable "deployment_safeguards_level" {
  description = "Warning (report) or Enforcement (block non-compliant deployments)."
  type        = string
  default     = "Warning"
  validation {
    condition     = contains(["Warning", "Enforcement"], var.deployment_safeguards_level)
    error_message = "deployment_safeguards_level must be Warning or Enforcement."
  }
}

variable "deployer_principal_ids" {
  description = "Pipeline identities that deploy the Helm release."
  type        = list(string)
  default     = []
}

variable "app_namespace" {
  type    = string
  default = "matterhub"
}
