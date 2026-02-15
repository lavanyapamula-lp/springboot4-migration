# Spring Boot 4 Migration Toolkit

Minimal, playbook-driven migration toolkit for issue-based migrations. No copilot-instructions or Copilot-specific tooling; the playbook is the single source of truth and can be applied manually or with any automation.

## What This Repository Contains

- `.github/workflows/springboot-java-migration-playbook.yml` - Workflow that creates a migration issue in the target repository.
- `migration-playbook.md` - Canonical migration rules and validation steps.
- `config/parent-pom-config.yml` - Parent POM coordinates and GitHub Packages source.
- `SpringBoot4-Migration-Strategy-Slides.md` - Slide content for the migration strategy (use to build or update the deck).

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
  version: "7.0.0"
```

2. Add repository secret in this repo:
   - `MIGRATION_PAT` (token that can create issues in target repositories)

## Running a Migration

1. Open Actions in this repository.
2. Run **Spring Boot / Java Migration** (workflow_dispatch).
3. Provide `target_repository` (for example `your-org/your-app`).

The workflow creates an issue in the target repository with migration instructions and a branch-specific playbook link. Perform the migration by following the playbook (manually or with your chosen tooling).

## Notes

- `MIGRATION_SUMMARY.md` is required output in target repository (enforced by playbook Rule 18.7).
- Parent POM must exist in GitHub Packages with coordinates matching `config/parent-pom-config.yml`.
