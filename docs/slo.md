# Service level objectives

SLOs describe the reliability users need, and the error budget tells us when to slow
down feature work and fix reliability instead.

## SLIs and SLOs

| SLI | Measured from | SLO (30-day rolling) |
|---|---|---|
| **Availability**: proportion of `/api/*` requests that do not return 5xx | `http_requests_total` (Prometheus) | **99.5%** |
| **Latency**: proportion of `/api/*` requests served in under 500 ms | `http_request_duration_seconds` histogram | **95%** |
| **Retention job freshness**: a successful run in the last 26 hours | `retention_job_complete` log event | **99%** of days |

99.5% allows about **3 hours 36 minutes** of errors per 30 days. The service supports
lawyers during working hours; a higher target would need multi-region active-active,
which is not justified for this service.

## Alerting on the error budget

Alerts fire on how fast the budget is being spent, not on single failures
([observability/prometheus/alerts.yml](../observability/prometheus/alerts.yml),
[infra/terraform/modules/alerts/prometheus_rules.tf](../infra/terraform/modules/alerts/prometheus_rules.tf)):

| Alert | Condition | Budget used if it continues | Response |
|---|---|---|---|
| Fast burn (Sev 1) | 5xx ratio > 14.4 x 0.5% over 1 h **and** 5 min | 2% in 1 hour | Page on-call now |
| Slow burn (Sev 3) | 5xx ratio > 6 x 0.5% over 6 h | 5% in 6 hours | Ticket, fix in working hours |
| High latency (Sev 3) | p95 > 500 ms for 10 min | n/a | Ticket |

The short 5-minute window on the fast-burn alert makes it reset quickly once the problem
is fixed, so on-call is not paged for an incident that is already over.

## Error budget policy

| Budget remaining | What happens |
|---|---|
| > 50% | Normal delivery |
| 25-50% | Reliability work is prioritised in the next sprint |
| < 25% | Only fixes and reliability changes are deployed to prod |
| Exhausted | Feature freeze until a postmortem's actions are done; the product owner agrees exceptions |

Budget status is reviewed at the fortnightly service review using the Grafana
"MatterHub - service overview" dashboard.
