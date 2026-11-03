# High error rate (5xx)

**Alerts:** `MatterHubErrorBudgetFastBurn` (Sev 1), `MatterHubErrorBudgetSlowBurn` (Sev 3), `lalert-matterhub-<env>-api-5xx`

**Meaning:** more than 0.5% of API requests are failing with server errors at a rate that
will exhaust the monthly error budget.

## Check

```bash
kubectl -n matterhub get pods -o wide                     # restarts? pending? one zone?
kubectl -n matterhub get events --sort-by=.lastTimestamp | tail -20
helm history matterhub -n matterhub --max 3               # recent deploy?
kubectl -n matterhub logs deploy/matterhub --since=15m | jq -c 'select(.level=="ERROR")' | head
```

Which routes and which errors? Run [`errors-by-route.kql`](../../observability/kql/errors-by-route.kql)
in Log Analytics; in App Insights, Failures > top exceptions. Pick one failing request's
`request_id` and follow it with [`trace-request.kql`](../../observability/kql/trace-request.kql).

| You see | Likely cause | Mitigate |
|---|---|---|
| Errors started at a deployment | Bad release | [rollback.md](rollback.md) |
| `OperationalError`, readiness failing | Database unreachable / exhausted / failing over | Check PostgreSQL metrics (CPU, connections, HA state). HA failover takes 60-120 s and recovers by itself |
| `password authentication failed` | Password rotated but pods not restarted | `kubectl -n matterhub rollout restart deploy/matterhub` ([secret-rotation.md](secret-rotation.md)) |
| Errors in one zone only | Zone or node problem | `kubectl cordon` the bad nodes; pods reschedule to healthy zones |
| OOMKilled pods | Memory limit too low / leak | [pod-crashloop.md](pod-crashloop.md) |

## Escalate

Sev 1 not mitigated in 30 minutes: incident lead pulls in the database / platform team.
Azure-side fault suspected: check Azure Service Health and raise a support ticket.
