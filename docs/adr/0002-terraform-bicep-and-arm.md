# ADR 0002: Terraform for the workload, Bicep for the foundation, ARM where it fits

- Status: accepted
- Date: 2026-11-03

## Context

The team uses Terraform, Bicep and ARM templates across different services. We need a
clear rule for which tool owns what, so resources are never managed by two tools.

## Decision

| Layer | Tool | Why |
|---|---|---|
| Subscription foundation: resource groups, Terraform state storage, Azure Policy, budgets, Defender plans | **Bicep** | Must exist *before* Terraform can run (chicken-and-egg of state). Azure-native, no state file, `what-if` previews, day-zero support for new resource types. Owned by the platform team. |
| Workload infrastructure: network, AKS, ACR, Key Vault, PostgreSQL, monitoring, alerts | **Terraform** | Rich module system, one plan across many resources, `for_each`, ephemeral values and write-only arguments, a mature ecosystem of policy tools (tflint, Checkov). |
| Log-search alert rules | **ARM JSON** | Alert rules are often designed in the portal and exported as ARM; keeping them as ARM lets the operations team round-trip them. Deployed with `AzureResourceManagerTemplateDeployment@3` / `az deployment group create`. |

Bicep compiles to ARM, so the two are the same deployment engine: `az bicep build`
produces ARM JSON (the CI pipeline publishes it as an artifact), and
`az bicep decompile` turns exported ARM into Bicep when we want to adopt a resource.

## Rules

1. A resource is owned by exactly one tool. Ownership is visible from tags
   (`managed-by = terraform | bicep | arm`).
2. Terraform reads Bicep-owned resources with `data` sources (for example the resource
   group) and never manages them.
3. Every tool runs from a pipeline with a preview (`terraform plan`, `what-if`) reviewed
   before apply.

## Consequences

- Engineers need to know both languages; they are small, and the split is by layer, not
  per resource, so context-switching is limited.
- Drift between tools is avoided by the ownership rule and the `managed-by` tag.
