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

variable "address_space" {
  description = "VNet address space."
  type        = list(string)
}

variable "subnet_cidrs" {
  description = "CIDRs for each subnet."
  type = object({
    aks               = string
    postgres          = string
    private_endpoints = string
  })
}

variable "tags" {
  type    = map(string)
  default = {}
}
