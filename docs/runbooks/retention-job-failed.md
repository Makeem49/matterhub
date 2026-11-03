# Retention job failed or did not run

**Alerts:** `MatterHubRetentionJobFailed` (job exited non-zero), `lalert-matterhub-<env>-retention-missing` (no success in 26 h).

**Impact:** closed matters past their retention date are not flagged for review. No user
impact; a records-management compliance risk if it persists.

```bash
kubectl -n matterhub get cronjob matterhub-retention        # SUSPEND? LAST SCHEDULE?
kubectl -n matterhub get jobs --sort-by=.status.startTime | tail -5
kubectl -n matterhub logs job/<job-name>
```

Run [`retention-job.kql`](../../observability/kql/retention-job.kql) for history.

| Cause | Fix |
|---|---|
| Database unavailable at 02:30 | Re-run when healthy: `kubectl -n matterhub create job --from=cronjob/matterhub-retention retention-manual` |
| CronJob suspended (after a restore) | `kubectl -n matterhub patch cronjob matterhub-retention -p '{"spec":{"suspend":false}}'` |
| Secret mount / identity error | See [secret-rotation.md](secret-rotation.md) and [api-unavailable.md](api-unavailable.md) |

The job is idempotent: re-running it never double-flags a matter.
