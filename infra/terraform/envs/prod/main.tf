terraform {
  required_version = ">= 1.11.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # Remote state in the storage account created by infra/bicep (blob lease = state lock).
  # Values are in backend.hcl:  terraform init -backend-config=backend.hcl
  backend "azurerm" {}
}

# Authentication comes from the environment: ARM_CLIENT_ID, ARM_TENANT_ID,
# ARM_SUBSCRIPTION_ID and ARM_USE_OIDC=true in pipelines (no client secrets).
provider "azurerm" {
  storage_use_azuread = true

  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}

module "platform" {
  source = "../../stack"

  environment                = var.environment
  location                   = var.location
  resource_group_name        = var.resource_group_name
  address_space              = var.address_space
  subnet_cidrs               = var.subnet_cidrs
  aks                        = var.aks
  aks_admin_group_object_ids = var.aks_admin_group_object_ids
  acr_sku                    = var.acr_sku
  private_data_plane         = var.private_data_plane
  postgres                   = var.postgres
  log_retention_days         = var.log_retention_days
  log_daily_quota_gb         = var.log_daily_quota_gb
  alert_email_addresses      = var.alert_email_addresses
  ops_group_object_id        = var.ops_group_object_id
}
