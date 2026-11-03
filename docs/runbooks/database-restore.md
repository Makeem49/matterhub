# Restore the database

**When:** data corruption, a destructive bad migration, or regional loss. A restore
always creates a **new** server; the original is never overwritten.

1. Declare an incident and agree the restore point with the service owner (data written
   after it will be lost).
2. Stop writes: scale the API to zero, suspend the CronJob.
   ```bash
   kubectl -n matterhub scale deploy/matterhub --replicas=0
   kubectl -n matterhub patch cronjob matterhub-retention -p '{"spec":{"suspend":true}}'
   ```
3. Restore:
   ```powershell
   ./scripts/powershell/Invoke-DatabaseRestoreDrill.ps1 -Environment prod -Mode PointInTime `
       -RestorePoint '2026-11-03T09:40:00Z' -TargetServerName psql-matterhub-prod-restored -KeepServer
   ```
   (`-Mode Geo` with the DR subnet and DNS zone for a regional failover.)
4. Validate from a pod in the VNet: row counts, latest `audit_events.occurred_at`.
5. Point the app at the restored server: `--set config.database.host=<restored fqdn>` via
   the pipeline, then bring Terraform in line (`terraform import` the new server, or
   rename back after copying data). Scale the API up and resume the CronJob.
6. Keep the old server until the postmortem is closed, then delete it.
