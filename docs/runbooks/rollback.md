# Roll back a deployment

Roll back first, debug later, whenever a release correlates with user impact.

## Application (Helm)

```bash
./scripts/rollback.sh            # previous revision, with confirmation, waits and runs helm test
./scripts/rollback.sh 41         # a specific revision (see: helm history matterhub -n matterhub)
```

Or re-run the CD workflow for the last good commit (it redeploys that image digest).

- Database migrations are not reverted. They are expand-only (ADR 0005), so the previous
  version runs against the newer schema.
- After rolling back, the next merge to `main` will redeploy the broken change. Revert the
  PR (or merge the fix) before anything else ships.

## Infrastructure (Terraform)

Terraform has no rollback: revert the PR and apply. For an urgent fix, revert in a PR
with priority review; the pipeline plans and applies the reverted code.

If an apply failed half-way, run the pipeline again: Terraform will plan only the
remaining difference. Never edit state by hand without a second engineer.

## Record

Note the rollback in the incident timeline and the release record.
