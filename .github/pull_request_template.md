## What and why
<!-- Link the ticket. What problem does this solve? -->

## How it was tested
<!-- Unit/integration tests, local kind cluster, dev environment, screenshots of dashboards -->

## Risk and rollback
- [ ] Safe to roll back with `helm rollback` / reverting this PR
- [ ] Database migration is expand-only (backwards compatible), or there is no migration
- [ ] Terraform plan reviewed: no unexpected `destroy` / `replace` (explain any below)

## Security
- [ ] No secrets, keys or personal data in code, logs or test fixtures
- [ ] New endpoints enforce authorisation; new identities have least privilege
- [ ] No new public network exposure

## Operability
- [ ] Logs/metrics added for new behaviour
- [ ] Alerts and runbooks updated for new failure modes
- [ ] Docs / README / ADR updated if behaviour or architecture changed
