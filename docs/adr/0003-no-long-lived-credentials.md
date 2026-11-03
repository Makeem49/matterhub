# ADR 0003: No long-lived credentials

- Status: accepted
- Date: 2026-11-03

## Context

Client secrets and storage keys leak through logs, screenshots, laptops and CI variables,
and they expire at inconvenient times. A government legal service needs to show who
accessed what, with credentials that cannot be reused outside their context.

## Decision

- Pipelines authenticate to Azure with **OIDC federation**: GitHub's token for
  `repo:<org>/matterhub:environment:<env>` is trusted by an Entra ID app; Azure DevOps uses
  workload identity federation service connections. Nothing to store or rotate.
- Separate identities for **plan** (read-only, used on pull requests) and **deploy**
  (contributor, only usable from an approved GitHub environment).
- Pods use **Microsoft Entra Workload ID**; nodes pull images with the kubelet identity.
- Storage accounts have **shared keys disabled**; Key Vault uses **Azure RBAC**.
- AKS **local accounts are disabled**; humans use Entra ID + Azure RBAC.
- The database password is the only secret. It is generated as an ephemeral value,
  written with write-only arguments (never in state), stored in Key Vault and mounted as
  a file (never a Kubernetes Secret, so never in etcd).

## Consequences

- One-off setup of federated credentials ([scripts/setup-pipeline-identity.sh](../../scripts/setup-pipeline-identity.sh)).
- Federated credential subjects must match exactly (environment names), which is a
  feature: a workflow on an unapproved branch cannot get a deploy token.
