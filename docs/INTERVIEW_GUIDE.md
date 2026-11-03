# Interview guide: DevOps Engineer (SEO), Government Legal Department

This guide turns the MatterHub project into interview evidence. Bracketed text such as
`[your example]` is for you to fill in with your own real experience; never present the
project as production work you did for an employer. It is a portfolio project: say so, and
say what it taught you.

---

## 1. What the panel will assess

From the advert:

| Stage | Format | Assessed on |
|---|---|---|
| **Stage 1** | Online technical assessment with the panel | The 7 technical skills from the Government Digital and Data Capability Framework (DevOps Engineer role) |
| **Stage 2** | Online interview + scenario-based exercises | Behaviour **Changing and Improving**, the key skills and experience, technical skills |

Essential experience: cloud delivery (Azure or similar), CI/CD (Azure DevOps, GitHub
Actions or similar), automation (PowerShell, Python, YAML, Bash), Git (branching, PRs,
code review), problem solving (incidents and improvements), collaboration in Agile teams.
Desirable: Docker / Kubernetes.

The capability framework describes the role as someone who delivers automated software
components that form part of a DevOps toolchain, turns technical requirements into DevOps
processes, manages live test environments and resolves issues that block delivery.
Check the expected level for each skill on the framework page:
https://ddat-capability-framework.service.gov.uk/development-operations-devops-engineer.html

---

## 2. Your opening (60-90 seconds)

> I'm a Python backend engineer with `[X]` years building and running services, most
> recently at `[AFEX / Sahel AI]`, where I `[built FastAPI services and Kafka/Debezium
> change-data-capture pipelines on AWS, containerised with Docker, deployed through
> `[your CI tool]`]`. I'm now finishing an MSc in Applied AI at Chester.
>
> The part of my work I enjoy most is the path from commit to production: automation,
> pipelines, making services observable and safe to change. My production cloud
> experience is mainly AWS, so to go deep on the Azure toolset in this role I built
> MatterHub: a legal-matter API on AKS with Terraform, Bicep and ARM, GitHub Actions and
> Azure DevOps pipelines, workload identity instead of secrets, SLO-based alerting and
> tested disaster recovery. I'd like to bring that mix of software engineering and
> operations to GLD's Digital, Data and Cyber team.

Keep it under 90 seconds. End on why GLD, not on a list of tools.

---

## 3. The 10-minute demo (if you can share your screen)

Practise this until it takes 8 minutes; leave 2 for questions.

1. **README diagram** (1 min): one environment, private data plane, identity everywhere.
2. **A pull request** (2 min): open `.github/workflows/ci.yml`. Change detection, then
   tests against real PostgreSQL, Trivy, kubeconform, Checkov, and one required check
   (`ci-passed`). "Only what you touch runs, so feedback stays fast."
3. **Delivery** (2 min): `cd.yml`. Build once, SBOM + provenance, deploy by **digest**,
   `helm upgrade --atomic`, `helm test`, smoke test proves the commit SHA is live,
   approval gate, `az acr import` promotes the identical image to prod.
4. **Security** (2 min): `modules/postgres/main.tf`: ephemeral password, write-only
   argument, so it is never in state. `_helpers.tpl`: secret mounted from Key Vault as a
   file, never a Kubernetes Secret. `config.py`: the app refuses to start in prod with
   auth disabled.
5. **Operations** (1 min): `observability/prometheus/alerts.yml` burn-rate alerts, each
   with a `runbook_url` that opens `docs/runbooks/high-error-rate.md`.
6. **DR** (1 min): `Invoke-DatabaseRestoreDrill.ps1` measures RTO/RPO and writes an
   evidence report. "A backup you haven't restored isn't a backup."

---

## 4. Job description → evidence → what to say

| "What you'll do" | Where in MatterHub | Talking point |
|---|---|---|
| CI/CD pipelines with Azure DevOps and GitHub Actions | `.github/workflows/*`, `azure-pipelines/*` | Same model in both: build once, promote by digest, environments with approvals. ADO uses templates (steps/jobs/stages), deployment jobs and Environment checks; GitHub uses a reusable workflow and a composite action. |
| IaC with Bicep, ARM, Terraform | `infra/bicep`, `infra/arm`, `infra/terraform`, ADR 0002 | Each tool owns one layer: Bicep for the subscription foundation (it must exist before Terraform state), Terraform for the workload, ARM for portal-exported alert rules. Bicep compiles to ARM. |
| Secure, scalable Azure infrastructure | `modules/network`, `modules/aks`, `modules/keyvault` | Private endpoints, delegated subnet for PostgreSQL, NSGs HTTPS-only, AKS with Entra RBAC and local accounts off, autoscaling node pools across zones. |
| Monitoring, logging, observability | `observability/`, `modules/monitoring`, `modules/alerts` | RED metrics by route template (bounded cardinality), JSON logs with request IDs, traces to App Insights, managed Prometheus, SLO burn-rate alerts. |
| Incidents, root cause, DR, business continuity | `docs/runbooks/`, `docs/disaster-recovery.md`, `scripts/rollback.sh` | Mitigate first (rollback), then root cause; blameless postmortems; RTO/RPO per scenario; quarterly restore drills with evidence. |
| Secure by design, vulnerability remediation, patching | `docs/security.md` | Trivy, pip-audit, CodeQL, Dependabot, hash-locked deps; AKS `patch` + `NodeImage` channels in maintenance windows with PDBs. |
| Access controls, identity, secrets management | ADR 0003, `modules/workload-identity`, `setup-pipeline-identity.sh` | OIDC federation (no secrets in CI), separate read-only plan identity, Workload ID for pods, namespace-scoped pipeline RBAC. |
| Release processes, source control, branching, code reviews | `CONTRIBUTING.md`, ADR 0004, PR template, CODEOWNERS | Trunk-based, Conventional Commits, squash merge, release notes generated from history, review checklist covering security and rollback. |
| Documentation, runbooks, support guides | `docs/` | Every alert links to a runbook with check / mitigate / escalate. |

---

## 5. The seven technical skills

For each skill: what it means, project evidence, and a prompt for your own example.
Panels value **real work experience** most. Use the project to show depth on Azure and to
fill gaps, and say clearly that it is a personal project.

### Development process optimisation
*Improving how software gets built, tested and released.*
- Project: change-detection CI (only affected jobs run), one aggregate required check,
  pre-commit hooks running the CI checks locally, build-once/promote-by-digest, release
  notes generated from Conventional Commits, Dependabot grouping to reduce PR noise.
- Your example: `[a time you made builds/deployments faster, safer or less manual, with a number: "deploy time from 40 min to 8", "from monthly to daily"]`.
- Likely question: *"How would you improve a pipeline that takes 45 minutes?"* Measure
  stage by stage first; parallelise independent jobs; cache dependencies and Docker
  layers; run only affected checks; move slow end-to-end tests to after merge; fail fast
  with lint before tests.

### Information security
*Protecting systems and data: identity, secrets, network, vulnerabilities, audit.*
- Project: section 4 rows on security; the STRIDE table in `docs/security.md`.
- Your example: `[how you handled credentials, access or a vulnerability at work]`.
- Likely question: *"How do you manage secrets in a pipeline?"* Avoid them: OIDC
  federation to Azure, managed identities for workloads. Where a secret must exist, keep it
  in Key Vault with RBAC, mount it at runtime, mask it in logs, scan for leaks, rotate it,
  and keep it out of Terraform state (write-only arguments, Terraform >= 1.11).

### Programming and build (software engineering)
*Writing, testing and building maintainable code.*
- Project: typed FastAPI service (strict mypy), 44 tests at 97% coverage with an 85% gate,
  migrations tested against SQLite and PostgreSQL with a schema-drift test, multi-stage
  Docker build with hash-locked dependencies, Pester and pytest for the scripts.
- Your example: `[a service or pipeline you built; your testing approach]`.

### Prototyping
*Exploring options quickly and cheaply to learn before committing.*
- Project: Docker Compose stack and a kind cluster that run the real Helm chart locally
  in minutes; dev environment on cheap SKUs with public endpoints; ADRs record options
  considered (Container Apps vs AKS).
- Your example: `[a spike or proof of concept that changed a decision]`.
- Framing: "I prototype to answer a specific question, time-box it, and write down what
  we learned so the decision outlives the prototype."

### Service support
*Keeping live services running: monitoring, incidents, problem management.*
- Project: SLOs and error budget policy, burn-rate alerts, runbooks, incident process
  with severities and roles, rollback script, postmortem template, DR drills.
- Your example: `[an incident you handled: detection, mitigation, root cause, what you changed afterwards]`.

### Systems integration
*Making components work together reliably.*
- Project: Entra ID tokens validated by the API; Key Vault ↔ CSI driver ↔ workload
  identity ↔ federated credential; ACR ↔ kubelet identity; Terraform outputs feeding Helm
  values in the pipeline; Prometheus metrics into Azure Monitor and Grafana.
- Your example: `[Kafka + Debezium CDC between systems, APIs between teams, etc.]`.

### User focus
*Understanding the needs of users, including internal users such as developers and ops.*
- Project: developers get fast feedback, a one-command local cluster and clear PR
  checklists; operators get runbooks linked from alerts; lawyers get an API with an
  immutable audit trail and least-privilege roles.
- Your example: `[a time you changed a solution after talking to its users]`.
- Framing: "For a platform team, the users are often the developers. I treat their
  friction (slow pipelines, unclear errors) as product feedback."

---

## 6. Behaviour: Changing and Improving

At SEO level this means: you look for better ways of working, challenge the status quo
constructively, take managed risks, encourage others to suggest improvements, and make
changes that last (documented, measured, adopted by the team).

**STAR, in about 4 minutes. Spend most of the time on Action, and say "I", not "we".**

| | |
|---|---|
| **Situation** (20 s) | Team, system, why it mattered |
| **Task** (20 s) | Your responsibility and the problem |
| **Action** (2-3 min) | What *you* did, how you brought people along, how you managed risk |
| **Result** (40 s) | Measurable outcome, what changed for users, what you learned |

### Example framework (fill in from your real work)

> **S:** At `[company]`, deployments of `[service]` were `[manual / slow / failing]`, which
> caused `[impact: outages, delays]`.
> **T:** I proposed and led `[automation / CI/CD / containerisation]`.
> **A:** I measured the current state (`[numbers]`); I built a small prototype on one
> service to show it worked; I agreed the approach with `[lead / team]`, addressed
> concerns about `[risk]` by `[rollback plan / gradual rollout]`; I wrote documentation
> and paired with colleagues so they could own it.
> **R:** `[Deploy time down X%, failed deployments down from N to M, adopted by K teams]`.
> I learned `[...]` and would next `[...]`.

### A project-based example (use it as a second example and label it a personal project)

> **S:** Building MatterHub, my first design stored the database password as a Kubernetes
> Secret created by Terraform, so it sat in Terraform state and in etcd.
> **T:** I wanted to remove every long-lived secret I could.
> **A:** I replaced pipeline credentials with OIDC federation, used workload identity for
> pods, generated the password as an ephemeral value with write-only arguments so it
> never reaches state, and mounted it from Key Vault as a file. I wrote ADR 0003 to record
> why, and a rotation runbook with a PowerShell script supporting `-WhatIf`.
> **R:** Zero secrets stored in GitHub, the cluster or Terraform state; rotation is one
> command. Next I would move to passwordless Entra authentication for PostgreSQL.

---

## 7. Technical question bank

**Azure and networking**
- *Managed identity vs service principal?* A managed identity is a service principal whose credentials Azure manages and rotates; nothing to store. System-assigned lives and dies with the resource; user-assigned is reusable and survives (I use user-assigned for AKS control plane and workloads).
- *How does AKS Workload ID work?* AKS issues a signed service account token (OIDC issuer). A federated credential on a managed identity trusts tokens with subject `system:serviceaccount:<ns>:<sa>`. The pod exchanges its token for an Entra access token. No secrets.
- *Private endpoint vs service endpoint?* A private endpoint gives the PaaS resource a private IP in your VNet and lets you disable public access; a service endpoint keeps the public IP but restricts the source subnet. Private endpoints need private DNS zones.
- *How does a pod reach PostgreSQL?* VNet-integrated (delegated subnet) Flexible Server, private DNS zone linked to the VNet, NSG allows 5432 only from the AKS subnet, NetworkPolicy allows egress only to that CIDR.

**CI/CD**
- *Continuous delivery vs deployment?* Delivery: every change is releasable, prod needs a decision. Deployment: every change goes to prod automatically. MatterHub is continuous deployment to dev, delivery to prod.
- *Why deploy by digest?* Tags are mutable; a digest is the image's content hash, so prod runs exactly what was tested.
- *Azure DevOps: stages, jobs, steps, templates, environments?* Stages contain jobs, jobs run on an agent and contain steps. Templates reuse steps, jobs, stages or variables. `deployment` jobs target an Environment that records history and holds approvals and checks (approvals, business hours, Azure Monitor alerts, exclusive lock).
- *How do you stop a bad deploy reaching users?* Tests and scans in CI, readiness probes, `maxUnavailable: 0`, `helm --atomic`, smoke test, approval gates, quick rollback, alerts on SLO burn.

**Infrastructure as code**
- *Terraform state: where, why, risks?* Remote state in Azure Storage with blob-lease locking, Entra-only access, versioning and soft delete. It maps config to real resources; it can hold sensitive values, so restrict access and keep secrets out with write-only arguments.
- *What is drift and how do you handle it?* Real resources differ from code. Detect with scheduled `terraform plan`; fix by reverting the manual change or codifying it; prevent with RBAC and Azure Policy.
- *Bicep vs ARM vs Terraform?* See ADR 0002. Bicep is a DSL that compiles to ARM, Azure-only, no state file, with `what-if`. Terraform is multi-cloud with state, modules and a plan/apply workflow.
- *`count` vs `for_each`?* `for_each` keys resources by name, so removing one item does not shift and recreate the others.

**Kubernetes and containers**
- *Liveness vs readiness vs startup probes?* Readiness controls traffic; liveness restarts a stuck container; startup protects slow starts. Never make liveness depend on the database, or a DB outage restarts every pod (`routers/health.py`).
- *PDB, HPA, topology spread?* PDB limits voluntary disruption (node upgrades); HPA scales on metrics; topology spread keeps replicas across zones and nodes.
- *How do you harden a container?* Minimal multi-stage image, non-root numeric UID, read-only root FS, drop all capabilities, no privilege escalation, seccomp RuntimeDefault, scan it, pin it by digest.
- *How do you troubleshoot `CrashLoopBackOff`?* `kubectl describe pod` (exit code, OOMKilled), `kubectl logs --previous`, events, recent changes. See `docs/runbooks/pod-crashloop.md`.

**Observability and incidents**
- *SLI vs SLO vs SLA?* SLI is the measurement, SLO the internal target, SLA the contractual promise with consequences.
- *Why burn-rate alerts?* They alert on user impact relative to the budget: fast burns page, slow burns raise tickets, and they don't fire for one-off blips.
- *Logs, metrics, traces?* Metrics tell you something is wrong, traces where, logs why. Correlation IDs join them up.
- *First steps in an incident?* Acknowledge, assess impact and severity, check recent changes, mitigate (often roll back), communicate on a cadence, root cause later in a blameless postmortem.

**Git**
- *Merge vs rebase vs squash?* Squash gives one commit per PR on `main` (clean history, easy revert); rebase updates a branch without merge commits; never rebase shared branches.
- *How do you review a PR?* Understand the intent, run it if needed, check tests, security, operability and rollback, give specific and kind feedback, approve when it improves `main`.

---

## 8. Scenario exercises (Stage 2)

Use a consistent structure: **clarify → stabilise → investigate → fix → prevent → communicate.**

1. **"A prod deploy at 4pm caused errors for some users."**
   Confirm impact on dashboards; roll back (`helm rollback`) because the deploy correlates;
   confirm recovery; inform stakeholders. Then reproduce in dev, find why tests missed it,
   add a test or a canary check, write the postmortem. Discuss whether late-afternoon
   deploys are wise (ADO business-hours check).
2. **"A developer committed a storage key to a public repo."**
   Rotate/revoke the key immediately (assume it is compromised); check access logs for
   misuse; remove from history (the key is still burned); inform security. Prevent:
   pre-commit secret scanning, push protection, and remove the need for keys (Entra-only,
   managed identity, shared keys disabled).
3. **"The team deploys manually from laptops. How would you introduce CI/CD?"**
   Talk to the team about pain points; start small with one service: CI for build and test,
   then automated deploy to dev, then gated prod; codify infra gradually (import existing
   resources); document, pair, show metrics. Don't do a big bang.
4. **"Azure costs doubled this month."**
   Cost Management by resource and tag; look for scale-out events, oversized SKUs, Log
   Analytics ingestion; fix; prevent with budgets, tags, ingestion caps, right-sizing,
   autoscaling minimums, reserved instances for steady load.
5. **"A critical CVE in the base image is announced."**
   Check exposure (Trivy / Defender: which images, which environments); rebuild on a patched
   base (Dependabot PR or manual bump); fast-track through the pipeline; verify scans are
   clean; record against the remediation SLA.
6. **"The database is slow after a release."**
   Compare before/after (App Insights dependencies, PostgreSQL slow query log); identify
   the query; roll back if user impact is high; add an index (expand-only migration);
   add a latency SLO alert if one was missing.

---

## 9. AWS to Azure (bridge your experience)

| AWS you know | Azure equivalent here |
|---|---|
| IAM roles for services / IRSA | Managed identities / Workload ID |
| IAM users + access keys | Avoided: Entra ID + OIDC federation |
| VPC, subnets, security groups | VNet, subnets, NSGs |
| PrivateLink / VPC endpoints | Private endpoints / service endpoints |
| EKS / ECR | AKS / ACR |
| RDS PostgreSQL | Azure Database for PostgreSQL Flexible Server |
| Secrets Manager / KMS | Key Vault |
| CloudWatch Logs / Metrics / X-Ray | Log Analytics (KQL) / Azure Monitor + managed Prometheus / Application Insights |
| CloudFormation | ARM templates / Bicep |
| CodePipeline / CodeBuild | Azure Pipelines / GitHub Actions |
| Organizations SCPs, Config rules | Management groups, Azure Policy |
| Glue / Athena | Data Factory / Synapse / Fabric |
| SageMaker | Azure Machine Learning |

Say it directly: "My production cloud is AWS; the concepts transfer one to one, and I've
built this Azure project end to end to learn the Azure specifics."

---

## 10. Gaps: be honest and show a plan

| Possible gap | How to answer |
|---|---|
| No production Azure experience | Transferable AWS experience + this project + the Azure learning path you are on (e.g. AZ-104 / AZ-400 `[if you are studying for them]`). |
| Kubernetes at scale | Ran the chart on kind and designed for AKS; explain the concepts precisely and say what you'd want to learn from the team. |
| PowerShell | The scripts here use `ShouldProcess`/`-WhatIf`, a module, PSScriptAnalyzer and Pester; Python and Bash are your stronger automation languages. |

---

## 11. Questions to ask the panel

- What does the current path from commit to production look like, and what would you most like to change in the first six months?
- How is the work split between Azure DevOps and GitHub Actions, and between Bicep and Terraform?
- How is on-call / out-of-hours support organised for the Digital, Data and Cyber team?
- How do developers, architects and the cyber team work together on secure-by-design reviews?
- What does success look like for this role after one year?

---

## 12. The day before

- [ ] Re-read the advert and this guide's sections 4-6.
- [ ] Prepare 2 real STAR examples for Changing and Improving, and one per essential skill.
- [ ] Run the demo once end to end; have the repo open in tabs.
- [ ] Test camera, microphone and screen sharing on the platform they use.
- [ ] Have the advert, your CV and your application statements to hand.
