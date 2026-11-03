# ADR 0004: Trunk-based development with short-lived branches

- Status: accepted
- Date: 2026-11-03

## Decision

- `main` is always releasable and protected: changes arrive only through pull requests.
- Branches are short-lived (hours to a couple of days) and named `type/short-description`
  (`feat/audit-endpoint`, `fix/readiness-timeout`, `infra/zone-redundant-pg`).
- PR titles follow Conventional Commits; we squash-merge, so the PR title becomes the
  commit message and feeds [release notes](../../scripts/python/release_notes.py).
- Required: one approving review from CODEOWNERS (two for `infra/` and workflows),
  the `ci-passed` check, resolved conversations, linear history, signed commits.
- Unfinished features ship dark behind configuration, not long-lived branches.
- Releases are continuous; the deployed version is the commit SHA plus a run number.

## Why not GitFlow

Long-lived `develop`/`release` branches delay integration, create merge pain and slow
feedback. With a fast CI pipeline, environment promotion of an immutable image gives the
same control GitFlow's release branches aimed for.

## Hotfixes

A hotfix is a normal PR to `main` with priority review; the pipeline is the fastest safe
path to prod. Rolling back (`helm rollback`) is the first response, a fix-forward PR the second.
