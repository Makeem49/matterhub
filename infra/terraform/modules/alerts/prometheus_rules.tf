# Same SLO rules as observability/prometheus/alerts.yml, deployed to Azure Monitor
# managed Prometheus. Keep the two in sync (CI greps both for each alert name).

locals {
  error_budget = 1 - var.slo_availability_target
  api          = "route=~\"/api/.*\""
}

resource "azurerm_monitor_alert_prometheus_rule_group" "recording" {
  name                = "prg-${var.name}-recording"
  location            = var.location
  resource_group_name = var.resource_group_name
  cluster_name        = var.aks_cluster_name
  scopes              = [var.monitor_workspace_id, var.aks_cluster_id]
  rule_group_enabled  = true
  interval            = "PT1M"
  tags                = var.tags

  rule {
    record     = "matterhub:http_errors:ratio_rate5m"
    expression = "sum(rate(http_requests_total{${local.api},status=~\"5..\"}[5m])) / clamp_min(sum(rate(http_requests_total{${local.api}}[5m])), 1e-9)"
  }
  rule {
    record     = "matterhub:http_errors:ratio_rate1h"
    expression = "sum(rate(http_requests_total{${local.api},status=~\"5..\"}[1h])) / clamp_min(sum(rate(http_requests_total{${local.api}}[1h])), 1e-9)"
  }
  rule {
    record     = "matterhub:http_errors:ratio_rate6h"
    expression = "sum(rate(http_requests_total{${local.api},status=~\"5..\"}[6h])) / clamp_min(sum(rate(http_requests_total{${local.api}}[6h])), 1e-9)"
  }
  rule {
    record     = "matterhub:http_latency_seconds:p95_5m"
    expression = "histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{${local.api}}[5m])))"
  }
}

resource "azurerm_monitor_alert_prometheus_rule_group" "alerts" {
  name                = "prg-${var.name}-alerts"
  location            = var.location
  resource_group_name = var.resource_group_name
  cluster_name        = var.aks_cluster_name
  scopes              = [var.monitor_workspace_id, var.aks_cluster_id]
  rule_group_enabled  = true
  interval            = "PT1M"
  tags                = var.tags

  rule {
    alert      = "MatterHubErrorBudgetFastBurn"
    expression = "matterhub:http_errors:ratio_rate1h > ${14.4 * local.error_budget} and matterhub:http_errors:ratio_rate5m > ${14.4 * local.error_budget}"
    for        = "PT2M"
    severity   = 1
    annotations = {
      summary     = "MatterHub is burning its error budget fast"
      runbook_url = "${var.runbook_base_url}/high-error-rate.md"
    }
    action {
      action_group_id = var.action_group_id
    }
    alert_resolution {
      auto_resolved   = true
      time_to_resolve = "PT10M"
    }
  }

  rule {
    alert      = "MatterHubErrorBudgetSlowBurn"
    expression = "matterhub:http_errors:ratio_rate6h > ${6 * local.error_budget}"
    for        = "PT15M"
    severity   = 3
    annotations = {
      summary     = "MatterHub error budget is burning steadily"
      runbook_url = "${var.runbook_base_url}/high-error-rate.md"
    }
    action {
      action_group_id = var.action_group_id
    }
  }

  rule {
    alert      = "MatterHubHighLatency"
    expression = "matterhub:http_latency_seconds:p95_5m > 0.5"
    for        = "PT10M"
    severity   = 3
    annotations = {
      summary     = "MatterHub p95 latency above 500 ms"
      runbook_url = "${var.runbook_base_url}/high-latency.md"
    }
    action {
      action_group_id = var.action_group_id
    }
  }

  rule {
    alert      = "MatterHubPodCrashLooping"
    expression = "increase(kube_pod_container_status_restarts_total{namespace=\"matterhub\"}[15m]) > 3"
    for        = "PT5M"
    severity   = 2
    annotations = {
      summary     = "A MatterHub container is restarting repeatedly"
      runbook_url = "${var.runbook_base_url}/pod-crashloop.md"
    }
    action {
      action_group_id = var.action_group_id
    }
  }

  rule {
    alert      = "MatterHubRetentionJobFailed"
    expression = "kube_job_status_failed{namespace=\"matterhub\", job_name=~\".*retention.*\"} > 0"
    for        = "PT1M"
    severity   = 3
    annotations = {
      summary     = "The retention CronJob failed"
      runbook_url = "${var.runbook_base_url}/retention-job-failed.md"
    }
    action {
      action_group_id = var.action_group_id
    }
  }
}
