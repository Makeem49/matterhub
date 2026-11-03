# Contributing

## Workflow

1. Pick up a ticket from the sprint board; move it to *In progress*.
2. Branch from `main`: `git switch -c feat/short-description` (`fix/`, `infra/`, `docs/`, `ci/`...).
3. Commit small, focused changes. Install the hooks once: `pip install pre-commit && pre-commit install --hook-type pre-commit --hook-type commit-msg`.
4. Open a pull request early (draft is fine). The title must be a
   [Conventional Commit](https://www.conventionalcommits.org): `feat(api): add audit trail endpoint`.
5. CI runs only what your change touches; `ci-passed` must be green.
6. Get the required review(s) (CODEOWNERS). Resolve every conversation.
7. **Squash-merge**. The PR title becomes the commit on `main`, which deploys to dev
   automatically and to prod after approval.

Branches should live hours or a few days. If a feature is not ready, merge it disabled
behind configuration rather than keeping a long-lived branch (ADR 0004).

## Commit / PR title types

`feat` `fix` `perf` `security` `infra` `ci` `docs` `refactor` `test` `chore` `build` `deps`.
Add `!` for breaking changes: `feat(api)!: require Matters.Read for audit trail`.

## Code review checklist

Authors fill in the PR template; reviewers check:

- **Correctness**: does it do what the ticket says? Are edge cases and failure paths tested?
- **Security**: input validation, authorisation on new endpoints, no secrets, least
  privilege for new identities/roles, no new public endpoints.
- **Operability**: logs with context, metrics for new behaviour, alert + runbook for new
  failure modes, docs updated.
- **Infrastructure**: read the `terraform plan` comment. Any `destroy` or `replace` must be
  explained in the PR. Is it safe to roll back?
- **Database**: migration is expand-only and backwards compatible (ADR 0005).
- **Simplicity**: is there a simpler way? Is it readable without the author?

Be kind and specific. Prefix optional suggestions with `nit:`. Approve when it is better
than what is on `main`, not when it is perfect.

## Branch protection on `main` (configure in GitHub settings)

- Require a pull request; 1 approval (CODEOWNERS); dismiss stale approvals on new commits
- Require status check `ci-passed`; require branches to be up to date
- Require conversation resolution; require linear history; require signed commits
- Do not allow bypass, including administrators
