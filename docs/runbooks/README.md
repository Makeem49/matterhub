# Runbooks

Every alert links to one of these pages. Each follows the same shape: **what it means,
how to check, how to mitigate, when to escalate**. Mitigate first, find root cause second.

| Runbook | Triggered by |
|---|---|
| [incident-response.md](incident-response.md) | Any Sev 1/2, or anything user-visible |
| [high-error-rate.md](high-error-rate.md) | `MatterHubErrorBudgetFastBurn`, `...SlowBurn`, `lalert-...-api-5xx` |
| [high-latency.md](high-latency.md) | `MatterHubHighLatency` |
| [api-unavailable.md](api-unavailable.md) | `MatterHubApiDown`, smoke test failure |
| [pod-crashloop.md](pod-crashloop.md) | `MatterHubPodCrashLooping` |
| [rollback.md](rollback.md) | A deployment made things worse |
| [secret-rotation.md](secret-rotation.md) | Scheduled rotation, suspected leak, `connections_failed` alert |
| [database-restore.md](database-restore.md) | Data corruption, bad migration, region loss |
| [retention-job-failed.md](retention-job-failed.md) | `MatterHubRetentionJobFailed`, `lalert-...-retention-missing` |
| [security-incident.md](security-incident.md) | Key Vault 403s, token-rejection spike, unexpected role assignment |

## Access you need before you are on call

```bash
az login
az aks get-credentials -g rg-matterhub-prod -n aks-matterhub-prod   # prod: from the jump host / VPN
kubelogin convert-kubeconfig -l azurecli
kubectl -n matterhub get pods                                       # Azure RBAC: "AKS RBAC Reader" or higher
```

Dashboards: Grafana "MatterHub - service overview", Azure portal > Application Insights
`appi-matterhub-prod` > Failures / Performance, Log Analytics `log-matterhub-prod`
(queries in [observability/kql](../../observability/kql/)).
