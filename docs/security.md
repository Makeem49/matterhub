# Security

MatterHub handles OFFICIAL and OFFICIAL-SENSITIVE legal data. Controls are built in from
the first commit (secure by design) and checked automatically in every pipeline run.

## Controls by layer

| Layer | Control | Where |
|---|---|---|
| **Identity** | Entra ID for humans and services; Azure RBAC on AKS; local accounts off | `modules/aks`, ADR 0003 |
| | OIDC federation for pipelines; separate read-only plan identity | `.github/workflows`, `scripts/setup-pipeline-identity.sh` |
| | Workload ID for pods; least-privilege roles (`Key Vault Secrets User` on one vault) | `modules/workload-identity` |
| | Pipeline is admin of the app namespace only, not the cluster | `modules/aks` (`deployer_namespace_admin`) |
| **Secrets** | Key Vault with RBAC, purge protection, audit logs; private endpoint | `modules/keyvault` |
| | DB password: ephemeral + write-only (never in state), mounted as a file (never in etcd) | `modules/postgres`, Helm `_helpers.tpl` |
| | Secret scanning on every PR (TruffleHog) and pre-commit (gitleaks) | `ci.yml`, `.pre-commit-config.yaml` |
| **Network** | Private PostgreSQL (VNet integration), Key Vault and ACR private endpoints | `modules/network`, `modules/postgres` |
| | NSGs: HTTPS only from the internet; PostgreSQL only from the AKS subnet | `modules/network` |
| | Kubernetes NetworkPolicy default-deny, Cilium-enforced | Helm `networkpolicy.yaml` |
| | Prod AKS API server private; pipelines run on self-hosted agents in the VNet | `envs/prod/terraform.tfvars` |
| **Workload** | Non-root (UID 10001), read-only root FS, all capabilities dropped, seccomp RuntimeDefault | `Dockerfile`, Helm values |
| | Pod Security Admission `restricted` on the namespace; AKS Deployment Safeguards | `deploy/cluster/namespace.yaml`, `modules/aks` |
| | Azure Policy pod security baseline initiative | `infra/bicep/modules/policy.bicep` |
| **Application** | JWT validation (RS256 only, issuer, audience, expiry); role-based authorisation | `app/src/matterhub/auth.py` |
| | Auth cannot be disabled in staging/prod (startup fails) | `app/src/matterhub/config.py` |
| | Strict input schemas (`extra="forbid"`), no hard deletes, append-only audit trail | `schemas.py`, `models.py` |
| | Security headers (HSTS, nosniff, frame-deny, CSP); request-ID sanitising | `observability.py` |
| | Internal endpoints (`/metrics`, health) not routed by the ingress | Helm `ingress.yaml` |
| **Data** | Encryption at rest (platform keys), TLS 1.2+ enforced on PostgreSQL, host encryption on nodes | `modules/postgres`, `modules/aks` |
| | UK regions only (Azure Policy + Terraform validation) | `policy.bicep`, `stack/variables.tf` |
| **Supply chain** | Hash-locked Python deps (`--require-hashes`) | `app/requirements.txt` |
| | Image SBOM + SLSA provenance; promote by digest | `cd.yml` |
| | Trivy image scan (CI, CD, weekly), pip-audit, CodeQL | `ci.yml`, `security.yml` |
| | IaC policy-as-code: Checkov, tflint, Bicep linter | `ci.yml`, `.checkov.yaml` |
| **Detection** | AKS audit logs (`kube-audit-admin`, `guard`), Key Vault audit, PostgreSQL logs | `modules/*` diagnostic settings |
| | Alerts: Key Vault 403s, token-rejection spikes, new role assignments | `infra/arm/log-alerts`, `modules/alerts` |
| | Defender for Containers, Key Vault, open-source databases | `infra/bicep/modules/defender.bicep` |

## Threat model (STRIDE, summary)

| Threat | Example | Mitigation |
|---|---|---|
| **Spoofing** | Forged or replayed token | Signature check against Entra JWKS, `aud`/`iss`/`exp`, RS256 only, 30 s leeway |
| **Tampering** | Altering a matter's history | Append-only audit table written in the same transaction; no delete endpoint; DB not reachable from outside the VNet |
| **Repudiation** | "I didn't close that matter" | Audit events carry the Entra identity; AKS audit logs; Key Vault audit |
| **Information disclosure** | Secret leaked from CI logs or state | No secrets in pipelines (OIDC); write-only DB password; masked outputs; secret scanning |
| **Denial of service** | Traffic spike or noisy neighbour | HPA, PDB, resource limits, ResourceQuota, connection pool limits, zone spread |
| **Elevation of privilege** | Compromised pod reaching the API server | No SA token mounted, non-root, no capabilities, NetworkPolicy, namespace-scoped pipeline RBAC |

## Vulnerability management and patching

| What | How | Cadence / SLA |
|---|---|---|
| Python dependencies | Dependabot PRs; pip-audit blocks merges | weekly; critical within 48 h |
| Base image (OS packages) | Dependabot bumps the tag; `apt-get upgrade` at build; Trivy blocks fixable HIGH/CRITICAL | weekly rebuild |
| Running images | Weekly Trivy scan; Defender for Containers | weekly |
| AKS control plane | `automatic_upgrade_channel = patch`, Sunday maintenance window | automatic |
| Node OS | `node_os_upgrade_channel = NodeImage`, Saturday window, PDBs keep the API up | weekly |
| Kubernetes minor versions | `scripts/python/aks_upgrade_report.py`; upgrade dev first, then prod | before end of support |
| PostgreSQL | Azure-managed minor versions in the Sunday maintenance window | automatic |
| GitHub Actions / Terraform providers | Dependabot | weekly |

Remediation SLAs follow severity: critical 2 days, high 7 days, medium 30 days.
Exceptions are recorded with an owner and expiry date (for Checkov, in `.checkov.yaml`).

## Hardening backlog

Known gaps, in priority order:

1. **Passwordless PostgreSQL**: use Entra ID authentication with the workload identity and
   drop the password entirely. Create a least-privilege application role (today the app
   uses the administrator login).
2. **Image signing**: sign with Notation and verify with Ratify/Azure Policy at admission.
3. **Pin GitHub Actions to commit SHAs** (Dependabot keeps them updated).
4. **Customer-managed keys** for PostgreSQL and node disks if the data owner requires it.
5. **Azure Firewall** for FQDN-filtered egress from AKS (today: NetworkPolicy allows 443 out).
6. **ABAC condition** on the deploy identity's role-assignment rights.
