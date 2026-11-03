# Disaster recovery and business continuity

## Objectives

| Scenario | RTO (back in service) | RPO (max data loss) |
|---|---|---|
| Pod / node failure | 0 (automatic) | 0 |
| Availability-zone failure | < 5 min (automatic) | 0 |
| Bad deployment | < 10 min (`helm rollback`) | 0 |
| Data corruption / bad migration | < 1 h (point-in-time restore) | the chosen restore point |
| Loss of the UK South region | < 8 h (rebuild in UK West) | < 1 h (geo-redundant backup lag) |
| Key Vault secret deleted | < 15 min (soft delete) | 0 |
| Terraform state lost or corrupted | < 1 h (blob versioning) | 0 |

## What makes these achievable

- **Zone redundancy**: AKS node pools and API pods spread across 3 zones (topology spread
  constraints), PDBs keep 2 API pods during maintenance, PostgreSQL zone-redundant HA
  with automatic failover (prod).
- **Backups**: PostgreSQL automated backups, 35 days retention in prod, **geo-redundant**
  to UK West. Key Vault soft delete (90 days) + purge protection. Terraform state with
  blob versioning, soft delete and a delete lock (GZRS).
- **Everything is code**: the whole platform can be recreated from this repository in
  another region by changing `location` and the address space.
- **Immutable images**: images are tagged by commit and deployed by digest; any version
  can be redeployed.

## Regional failover procedure (UK South lost)

1. Declare a major incident ([runbooks/incident-response.md](runbooks/incident-response.md)).
   Incident lead decides to fail over (this is a business decision: RPO up to 1 h).
2. Create `envs/dr` from `envs/prod` with `location = "ukwest"`, a non-overlapping address
   space, and `resource_group_name = "rg-matterhub-dr"` (resource group via Bicep:
   add `dr` to `environments`).
3. `terraform apply` the DR environment **without** the PostgreSQL module, then
   geo-restore the database into the new delegated subnet:
   `./scripts/powershell/Invoke-DatabaseRestoreDrill.ps1 -Environment prod -Mode Geo -KeepServer -TargetSubnetId ... -TargetPrivateDnsZoneId ...`
   and import the restored server into Terraform state.
4. Re-import images into the DR registry (`az acr import`) and run the CD workflow
   against the `dr` environment.
5. Point DNS at the DR ingress; verify with `scripts/smoke-test.sh`.
6. When UK South returns, plan fail-back as a normal, scheduled change.

## Testing

Untested backups are not backups.

| Drill | How | Frequency | Evidence |
|---|---|---|---|
| Point-in-time restore | `Invoke-DatabaseRestoreDrill.ps1 -Mode PointInTime` | quarterly | markdown report attached to the service review |
| Geo-restore to UK West | `Invoke-DatabaseRestoreDrill.ps1 -Mode Geo` | twice a year | report + time to rebuild |
| Zone failure | `az aks nodepool` cordon/drain one zone in dev; PostgreSQL forced failover in dev | quarterly | dashboard screenshots, no SLO breach |
| Rollback | `scripts/rollback.sh` in dev | every release train | pipeline logs |
| Secret rotation | `Invoke-DatabasePasswordRotation.ps1 -Environment dev` | quarterly | Key Vault version tags |

After the restore, validate the data from a pod inside the VNet: row counts per table and
the most recent `audit_events.occurred_at` (which is the real achieved RPO).
