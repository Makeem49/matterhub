# KQL query library

Saved Log Analytics queries for investigating MatterHub in Azure. The app writes one
JSON object per line to stdout. Container Insights collects it into
`ContainerLogV2`, where `LogMessage` is already parsed as dynamic JSON.

| File | Use it when |
|---|---|
| `errors-by-route.kql` | an error-rate alert fires: which routes and status codes? |
| `trace-request.kql` | you have an `X-Request-ID` from a user or a log line |
| `slow-requests.kql` | the latency alert fires |
| `pod-restarts.kql` | pods are crash-looping or being OOM-killed |
| `access-denied.kql` | security review: 401/403 spikes, who was denied |
| `retention-job.kql` | the retention CronJob failed or did nothing |

Run them in the portal (Log Analytics workspace > Logs) or from the CLI:

```bash
az monitor log-analytics query -w <workspace-guid> --analytics-query @observability/kql/errors-by-route.kql
```
