# Spring Boot 4 Migration Toolkit

Minimal, playbook-driven migration toolkit for GitHub Copilot issue-based migrations.

## What This Repository Contains

- `.github/workflows/copilot-migrate-repo.yml` - Workflow that creates a migration issue in the target repository.
- `migration-playbook.md` - Canonical migration rules and validation steps.
- `config/parent-pom-config.yml` - Parent POM coordinates and GitHub Packages source.

## Standard Approach

- Keep migration logic in `migration-playbook.md` (single source of truth).
- Use workflow to create a thin issue with:
  - target repository context
  - parent POM resolution instructions
  - branch-specific link to `migration-playbook.md`
- Keep credentials/runtime Maven settings ephemeral (`~/.m2/settings.xml`) and do not commit them.

## One-Time Setup

1. Configure `config/parent-pom-config.yml`:

```yaml
parent_pom:
  owner: "your-org-or-user"
  repository: "springboot-test-parent"
  groupId: "com.example"
  artifactId: "springboot-test-parent"
  version: "2.0.0"
```

2. Add repository secret in this repo:
   - `MIGRATION_PAT` (token that can create issues in target repositories)

## Running a Migration

1. Open Actions in this repository.
2. Run `Copilot Migration Trigger`.
3. Provide `target_repository` (for example `your-org/your-app`).

The workflow creates an issue in the target repository with migration instructions and a branch-specific playbook link.

## Notes

- `MIGRATION_SUMMARY.md` is required output in target repository (enforced by playbook Rule 18.7).
- Parent POM must exist in GitHub Packages with coordinates matching `config/parent-pom-config.yml`.
