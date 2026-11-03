# AKS cluster hardened for a government workload:
# * Entra ID authentication + Azure RBAC for Kubernetes; local accounts disabled
# * OIDC issuer + Workload Identity (pods use federated tokens, no secrets)
# * Azure CNI Overlay with Cilium (NetworkPolicy enforcement, eBPF data plane)
# * Azure Policy add-on (pod security baseline), Key Vault CSI driver with rotation
# * Auto-upgrade: patch channel for Kubernetes, NodeImage for OS security patches,
#   both inside planned maintenance windows
# * Container Insights (logs) and managed Prometheus (metrics)

resource "azurerm_user_assigned_identity" "control_plane" {
  name                = "id-aks-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# The control plane manages load balancers / IPs in our subnet.
resource "azurerm_role_assignment" "control_plane_network" {
  scope                = var.subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
}

resource "azurerm_kubernetes_cluster" "this" {
  name                         = "aks-${var.name}"
  location                     = var.location
  resource_group_name          = var.resource_group_name
  dns_prefix                   = var.name
  kubernetes_version           = var.kubernetes_version
  sku_tier                     = var.sku_tier
  node_resource_group          = "rg-${var.name}-aks-nodes"
  automatic_upgrade_channel    = "patch"
  node_os_upgrade_channel      = "NodeImage"
  oidc_issuer_enabled          = true
  workload_identity_enabled    = true
  local_account_disabled       = true
  azure_policy_enabled         = true
  image_cleaner_enabled        = true
  image_cleaner_interval_hours = 48
  private_cluster_enabled      = var.private_cluster_enabled
  run_command_enabled          = true # `az aks command invoke` for break-glass on private clusters
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.control_plane.id]
  }

  azure_active_directory_role_based_access_control {
    tenant_id              = var.tenant_id
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  dynamic "api_server_access_profile" {
    for_each = !var.private_cluster_enabled && length(var.api_server_authorized_ip_ranges) > 0 ? [1] : []
    content {
      authorized_ip_ranges = var.api_server_authorized_ip_ranges
    }
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_pool.vm_size
    vnet_subnet_id               = var.subnet_id
    zones                        = var.zones
    auto_scaling_enabled         = true
    min_count                    = var.system_pool.min_count
    max_count                    = var.system_pool.max_count
    only_critical_addons_enabled = true # system pods only; apps go to the user pool
    os_sku                       = "AzureLinux"
    os_disk_type                 = "Ephemeral"
    host_encryption_enabled      = true # encrypts temp disks and caches at the VM host
    max_pods                     = 110
    temporary_name_for_rotation  = "systemtmp"
    tags                         = var.tags

    upgrade_settings {
      max_surge                = "33%"
      drain_timeout_in_minutes = 30
    }
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = "192.168.0.0/16"
    service_cidr        = "172.16.0.0/16"
    dns_service_ip      = "172.16.0.10"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  monitor_metrics {}

  # "Manual" = node pools below + cluster autoscaler. "Auto" would enable Node Auto
  # Provisioning (Karpenter), which picks VM sizes per workload.
  node_provisioning_profile {
    mode = "Manual"
  }

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  # Managed NGINX ingress (application routing add-on) with Key Vault TLS certificates.
  web_app_routing {
    dns_zone_ids = []
  }

  dynamic "microsoft_defender" {
    for_each = var.defender_enabled ? [1] : []
    content {
      log_analytics_workspace_id = var.log_analytics_workspace_id
    }
  }

  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "01:00"
    utc_offset  = "+00:00"
  }

  maintenance_window_node_os {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Saturday"
    start_time  = "01:00"
    utc_offset  = "+00:00"
  }

  lifecycle {
    ignore_changes = [default_node_pool[0].node_count] # owned by the cluster autoscaler
  }

  depends_on = [azurerm_role_assignment.control_plane_network]
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                    = "user"
  kubernetes_cluster_id   = azurerm_kubernetes_cluster.this.id
  mode                    = "User"
  vm_size                 = var.user_pool.vm_size
  vnet_subnet_id          = var.subnet_id
  zones                   = var.zones
  auto_scaling_enabled    = true
  min_count               = var.user_pool.min_count
  max_count               = var.user_pool.max_count
  os_sku                  = "AzureLinux"
  os_disk_type            = "Ephemeral"
  host_encryption_enabled = true
  max_pods                = 110
  tags                    = var.tags

  upgrade_settings {
    max_surge                = "33%"
    drain_timeout_in_minutes = 30
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}

# --------------------------------------------------- control plane audit logs

resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                           = "diag-to-log-analytics"
  target_resource_id             = azurerm_kubernetes_cluster.this.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "kube-audit-admin" # every write to the API server (who changed what)
  }
  enabled_log {
    category = "guard" # Entra ID authentication decisions
  }
  enabled_log {
    category = "cluster-autoscaler"
  }
}

# ------------------------------------------------ Container Insights (logs)

resource "azurerm_monitor_data_collection_rule" "container_insights" {
  name                = "MSCI-${var.location}-aks-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  destinations {
    log_analytics {
      name                  = "ciworkspace"
      workspace_resource_id = var.log_analytics_workspace_id
    }
  }

  data_flow {
    streams      = local.container_insights_streams
    destinations = ["ciworkspace"]
  }

  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      extension_name = "ContainerInsights"
      streams        = local.container_insights_streams
      extension_json = jsonencode({
        dataCollectionSettings = {
          interval               = "1m"
          namespaceFilteringMode = "Include"
          namespaces             = var.container_insights_namespaces
          enableContainerLogV2   = true
        }
      })
    }
  }
}

locals {
  container_insights_streams = [
    "Microsoft-ContainerLogV2",
    "Microsoft-KubeEvents",
    "Microsoft-KubePodInventory",
    "Microsoft-KubeNodeInventory",
    "Microsoft-InsightsMetrics",
    "Microsoft-Perf",
  ]
}

resource "azurerm_monitor_data_collection_rule_association" "container_insights" {
  name                    = "ContainerInsightsExtension"
  target_resource_id      = azurerm_kubernetes_cluster.this.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.container_insights.id
}

# ----------------------------------------- Azure Monitor managed Prometheus

resource "azurerm_monitor_data_collection_endpoint" "prometheus" {
  name                = "dce-prom-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "Linux"
  tags                = var.tags
}

resource "azurerm_monitor_data_collection_rule" "prometheus" {
  name                        = "dcr-prom-${var.name}"
  location                    = var.location
  resource_group_name         = var.resource_group_name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.prometheus.id
  kind                        = "Linux"
  tags                        = var.tags

  destinations {
    monitor_account {
      name               = "MonitoringAccount1"
      monitor_account_id = var.monitor_workspace_id
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["MonitoringAccount1"]
  }

  data_sources {
    prometheus_forwarder {
      name    = "PrometheusDataSource"
      streams = ["Microsoft-PrometheusMetrics"]
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "prometheus" {
  name                    = "dcra-prom-${var.name}"
  target_resource_id      = azurerm_kubernetes_cluster.this.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.prometheus.id
}

# ------------------------------------------------------ deployment safeguards
# AKS Deployment Safeguards (Azure Policy under the hood) check every workload against
# best practice: resource limits, probes, no :latest tags, restricted pod security.
resource "azurerm_kubernetes_cluster_deployment_safeguard" "this" {
  kubernetes_cluster_id        = azurerm_kubernetes_cluster.this.id
  level                        = var.deployment_safeguards_level
  pod_security_standards_level = "Restricted"
  excluded_namespaces          = ["kube-system", "app-routing-system"]
}

# ------------------------------------------------------ pipeline access (Azure RBAC)
# The deployment identity can fetch a kubeconfig and administer ONLY the app namespace.
# It cannot create namespaces, change cluster-wide RBAC or touch kube-system.
resource "azurerm_role_assignment" "deployer_cluster_user" {
  for_each             = toset(var.deployer_principal_ids)
  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "deployer_namespace_admin" {
  for_each             = toset(var.deployer_principal_ids)
  scope                = "${azurerm_kubernetes_cluster.this.id}/namespaces/${var.app_namespace}"
  role_definition_name = "Azure Kubernetes Service RBAC Admin"
  principal_id         = each.value
}
