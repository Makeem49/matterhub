# ADR 0005: Database migrations run as a Helm pre-upgrade hook

- Status: accepted
- Date: 2026-11-03

## Options considered

1. App runs migrations on startup: every replica races to migrate; a bad migration
   crash-loops the whole deployment.
2. Init container: same race, repeated on every pod start.
3. Pipeline step before `helm upgrade`: needs network access to a private database from
   the runner and duplicates configuration.
4. **Helm `pre-install,pre-upgrade` hook Job**: runs once, inside the cluster, with the
   same image and configuration as the release, before new pods start.

## Decision

Option 4. Hooks run before the release's regular resources exist, so the hook brings its
own ServiceAccount and SecretProviderClass (hook weight -20) ahead of the Job (-10);
Terraform creates a federated credential for the `matterhub-migrate` ServiceAccount.

## Rules for migrations

- **Expand/contract**: a release may only add (nullable columns, new tables, indexes
  created concurrently). Removing or renaming happens in a later release, after no
  running version uses the old shape. This is what makes `helm rollback` safe without
  reverting the schema.
- A CI test fails if models and migrations drift (`test_models_and_migrations_are_in_sync`).
- Migrations are tested against SQLite and PostgreSQL in CI.

## Consequences

- If the hook fails, `helm upgrade --atomic` aborts and the previous release keeps
  running; the failed Job is kept for its logs (`hook-delete-policy: before-hook-creation,hook-succeeded`).
