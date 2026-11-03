# Rotate the database password

**When:** quarterly (scheduled), immediately on a suspected leak, or when
`alert-matterhub-<env>-psql-conn-failed` fires after a partial rotation.

## Option A: runbook script (fast, any time)

```powershell
Connect-AzAccount
./scripts/powershell/Invoke-DatabasePasswordRotation.ps1 -Environment prod -Reason "Quarterly rotation" -WhatIf
./scripts/powershell/Invoke-DatabasePasswordRotation.ps1 -Environment prod -Reason "Quarterly rotation"
```

It generates a password in memory, stores it as a new Key Vault version (tagged with who,
when and why), updates PostgreSQL, rolling-restarts the API and waits until all pods are
Ready. Existing pooled connections keep working; expect a few seconds of failed new
connections between the server update and the restart. In prod, run it in a quiet period.

## Option B: Terraform (planned)

Increment `postgres.password_version` in `envs/<env>/terraform.tfvars` in a PR. The
apply generates a new password and writes it to PostgreSQL and Key Vault (write-only:
it never appears in state or the plan). Then restart the API:
`kubectl -n matterhub rollout restart deploy/matterhub`.

## If it goes wrong

| Symptom | Fix |
|---|---|
| Script failed at the PostgreSQL step | Disable the new Key Vault version (command printed by the script); pods keep using the previous one |
| Pods not Ready after restart, `password authentication failed` | Key Vault and server disagree: set the server password to the latest Key Vault value (`Update-AzPostgreSqlFlexibleServer`), then restart |
| CronJob failed overnight | It picks up the new secret on the next run; re-run now with `kubectl -n matterhub create job --from=cronjob/matterhub-retention retention-manual` |
