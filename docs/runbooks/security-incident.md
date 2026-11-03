# Security incident

**Alerts:** Key Vault 403s (`lalert-...-keyvault-denied`), token-rejection spike
(`lalert-...-auth-failures`), role assignment created (`alert-...-role-assignment`),
Defender for Cloud alerts. Also: a secret found in a commit, PR or log.

## Immediately

1. **Contain, preserve evidence.** Do not delete logs or resources. Note times in UTC.
2. Inform the security team / SOC and the incident lead. If personal data may be
   affected, inform the Data Protection Officer straight away.
3. Credential exposed? **Rotate first** ([secret-rotation.md](secret-rotation.md)), then
   investigate. For a leaked Entra ID credential, revoke sessions and disable the principal.

## Investigate

```kusto
// Who read secrets, from where (Key Vault audit)
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT" and OperationName == "SecretGet"
| project TimeGenerated, identity_claim_oid_g, CallerIPAddress, ResultSignature, requestUri_s
| order by TimeGenerated desc
```

- Kubernetes changes: `AKSAuditAdmin` table (who changed what in the cluster).
- Azure changes: Activity log (role assignments, network rule changes).
- App access: [`access-denied.kql`](../../observability/kql/access-denied.kql) for denied
  principals and reasons.

## Afterwards

Postmortem with the security team; add a detection or preventive control for the gap
(for example a new Checkov rule, Azure Policy or alert).
