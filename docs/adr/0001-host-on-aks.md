# ADR 0001: Host the service on AKS

- Status: accepted
- Date: 2026-11-03

## Context

MatterHub is a containerised API plus two batch workloads (database migration, daily
retention job). Candidate platforms: Azure App Service, Azure Container Apps, AKS.

## Decision

Use **AKS**, with the application routing add-on, Workload ID, Key Vault CSI driver,
managed Prometheus and Azure Policy add-ons.

## Reasons

- The department already runs several services; a shared, governed Kubernetes platform
  amortises the operational cost and gives one deployment model (Helm) for all of them.
- We need fine-grained network control (NetworkPolicy, private API server), Pod Security
  "restricted", and Deployment Safeguards, which are first-class on AKS.
- Jobs and CronJobs with `concurrencyPolicy: Forbid` and hook ordering fit the migration
  and retention workloads exactly.

## Consequences

- More to operate than App Service or Container Apps: node pools, upgrades, add-ons. We
  mitigate with auto-upgrade channels (`patch`, `NodeImage`), planned maintenance windows,
  PDBs and runbooks.
- **If MatterHub were the only service, Azure Container Apps would be the simpler, cheaper
  choice.** The Helm chart and container image would move across with little change.
