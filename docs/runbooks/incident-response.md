# Incident response

## Severity

| Sev | Definition | Response |
|---|---|---|
| 1 | Service down or data at risk for all users | Page on-call immediately, incident lead + comms lead, updates every 30 min |
| 2 | Major feature broken or many users affected | On-call within 30 min, updates hourly |
| 3 | Degraded, workaround exists | Next working day |
| 4 | Cosmetic / no user impact | Backlog |

## First 15 minutes

1. **Acknowledge** the alert so others know it is owned.
2. **Open an incident channel** (`#inc-YYYYMMDD-short-name`) and start a timeline: every
   action and observation with a UTC timestamp.
3. **Assess impact**: who is affected, since when, is data at risk? Set the severity.
4. **Was there a recent change?** Check the last deployments and infra applies:
   `helm history matterhub -n matterhub`, GitHub Actions runs, Azure activity log.
   If a change correlates, **roll back first** ([rollback.md](rollback.md)), investigate after.
5. **Communicate**: post a short status for the service owner and users (what is
   affected, what we are doing, next update time). Do not speculate on cause.

## Roles (Sev 1/2)

- **Incident lead**: coordinates, decides, keeps the timeline. Does not debug.
- **Operations**: investigates and mitigates.
- **Comms**: updates stakeholders on the agreed cadence.

## Closing

- Confirm recovery with metrics (error rate back under SLO, smoke test passing).
- Stand down, post a final update.
- Sev 1/2: blameless postmortem within 5 working days using
  [../postmortem-template.md](../postmortem-template.md). Actions get owners and dates
  and go into the backlog; the error budget policy ([../slo.md](../slo.md)) may freeze features.
- If personal data may have been exposed, inform the Data Protection Officer immediately
  (GDPR 72-hour reporting clock) and the security team ([security-incident.md](security-incident.md)).
