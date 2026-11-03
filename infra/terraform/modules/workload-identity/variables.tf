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

variable "oidc_issuer_url" {
  description = "AKS OIDC issuer that signs the service account tokens."
  type        = string
}

variable "namespace" {
  type    = string
  default = "matterhub"
}

variable "service_accounts" {
  description = "Kubernetes service accounts allowed to use this identity (API + migration hook)."
  type        = list(string)
  default     = ["matterhub", "matterhub-migrate"]
}

variable "key_vault_id" {
  type = string
}
