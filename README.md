# Spring Boot 4 Migration Service

> A centralized repository that migrates **any** Spring Boot 3 / Java 21 application to Spring Boot 4 / Java 25 via a GitHub Actions workflow dispatch.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│   springboot4-migration (THIS REPO)                                  │
│   ─────────────────────────────────                                  │
│   Contains all migration logic, scripts, playbooks, and the          │
│   GitHub Actions workflow. Acts as a reusable migration service.     │
│                                                                      │
│   Trigger: workflow_dispatch with target repo as input               │
│                                                                      │
│         ┌─────────────┐      ┌─────────────┐      ┌──────────────┐  │
│         │ migrate.sh   │      │ OpenRewrite  │      │ validation   │  │
│         │ (mechanical) │ ───► │ (AST-level)  │ ───► │ (checks)     │  │
│         └─────────────┘      └─────────────┘      └──────────────┘  │
│                                        │                             │
│                                        ▼                             │
│                              Creates PR on target repo               │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
                                        │
         ┌──────────────────────────────┼──────────────────────────────┐
         ▼                              ▼                              ▼
┌─────────────────┐          ┌─────────────────┐          ┌─────────────────┐
│  team-a/app-1   │          │  team-b/app-2   │          │  team-c/app-3   │
│  (target repo)  │          │  (target repo)  │          │  (target repo)  │
│                 │          │                 │          │                 │
│  Gets a PR with │          │  Gets a PR with │          │  Gets a PR with │
│  all migration  │          │  all migration  │          │  all migration  │
│  changes        │          │  changes        │          │  changes        │
└─────────────────┘          └─────────────────┘          └─────────────────┘
```

## Repository Structure

```
springboot4-migration/
├── .github/
│   └── workflows/
│       ├── migrate-target-repo.yml       # Main automated workflow
│       └── copilot-migrate-repo.yml      # Copilot-based workflow (creates issue)
├── config/
│   ├── parent-pom-config.yml             # ⭐ Parent POM configuration (edit this!)
│   ├── maven-settings-github-packages.xml # Maven settings template
│   ├── openrewrite-init.gradle           # Gradle OpenRewrite init script
│   └── copilot-instructions.md           # Copilot instructions
├── scripts/
│   ├── migrate.sh                        # Mechanical migration script
│   ├── validate.sh                       # Post-migration validation
│   └── generate-pr-body.sh               # PR description generator
├── migration-playbook.md                 # Full playbook reference
├── PRE_MIGRATION_CHECKLIST.md            # Prerequisites before migration
├── GITHUB_PACKAGES_SETUP.md              # How to publish parent POM to GitHub Packages
└── README.md                             # This file
```

### Key Configuration File

**`config/parent-pom-config.yml`** - Edit this file once with your organization's parent POM details. All workflows automatically use this configuration.

## Prerequisites

Before migrating any target repository, ensure:

1. **Parent POM (if used)** is already migrated to Spring Boot 4 and published to **GitHub Packages**:
   - Published at: `https://maven.pkg.github.com/OWNER/REPO`
   - Version: `2.0.0-SNAPSHOT` (or your target version)
   - **Why GitHub Packages?** The agent can authenticate using `GITHUB_TOKEN` automatically
   - See `GITHUB_PACKAGES_SETUP.md` for publishing instructions

2. **Java 25** is installed in your CI/CD environment and locally

3. **Maven 3.9+** or **Gradle 8.14+** is available

4. Target repository has a clean working directory (no uncommitted changes)

📋 **See `PRE_MIGRATION_CHECKLIST.md` for full details**

### Alternative: Nexus/Artifactory

If your parent POM is in private Nexus:
- ⚠️ Agent cannot access private Nexus (no credentials)
- Agent will apply code changes but skip compilation
- Compilation validated in your CI/CD (which has credentials)

---

## Setup Instructions

### Step 1: Create the Migration Repository

```bash
# Create the repo on GitHub (or via UI)
gh repo create YOUR_ORG/springboot4-migration --private --clone
cd springboot4-migration
```

---

### Step 2: Configure Parent POM Details (One-Time Setup)

**⭐ IMPORTANT**: Edit `config/parent-pom-config.yml` with your organization's parent POM details:

```yaml
parent_pom:
  owner: "yourorg"                         # Change to your GitHub org
  repository: "springboot-test-parent" # Change to your parent POM repo
  groupId: "com.example"                   # Change to your groupId
  artifactId: "springboot-test-parent" # Change to your artifactId
  version: "2.0.0-SNAPSHOT"                # Your migrated version
```

**Commit this file:**
```bash
git add config/parent-pom-config.yml
git commit -m "Configure parent POM details for organization"
git push
```

**This configuration will be automatically used by all workflows - no need to enter these details when triggering migrations!**

---

### Step 3: Create a Personal Access Token (PAT) or GitHub App

The workflow needs to clone, push, and create PRs on **other** repositories.
You have two options:

#### Option A: Fine-Grained Personal Access Token (Simpler)

1. Go to GitHub → Settings → Developer Settings → Personal Access Tokens → Fine-grained tokens
2. Click "Generate new token"
3. Configure:
   - **Token name:** `springboot4-migration-bot`
   - **Expiration:** Set as appropriate
   - **Repository access:** Select "All repositories" OR specific repos you want to migrate
   - **Permissions:**
     - **Contents:** Read and Write
     - **Pull Requests:** Read and Write
     - **Metadata:** Read-only
4. Generate and copy the token

#### Option B: GitHub App (Recommended for Organizations)

1. Go to your Org Settings → Developer Settings → GitHub Apps → New GitHub App
2. Configure:
   - **Name:** `Spring Boot 4 Migration Bot`
   - **Permissions:**
     - Repository: Contents (Read & Write), Pull Requests (Read & Write), Metadata (Read)
   - **Where can this app be installed:** Only on this account
3. Install the app on all repos you want to migrate
4. Generate a private key
5. Note the App ID and Installation ID

### Step 4: Add the Secret to the Migration Repo

Go to **springboot4-migration** repo → Settings → Secrets and Variables → Actions:

- For PAT: Add secret named `MIGRATION_PAT` with the PAT value
- For GitHub App: Add secrets `APP_ID` and `APP_PRIVATE_KEY`

### Step 5: Copy All Files Into the Repo

```bash
# Create directory structure
mkdir -p .github/workflows scripts config

# Copy the files from this toolkit into the correct locations
# (see the file contents below)

# Commit and push
git add -A
git commit -m "Initial migration toolkit setup"
git push origin main
```

## Quick Start

### 1. Configure Your Parent POM (One-Time Setup)

Edit `config/parent-pom-config.yml` with your organization's details:

```yaml
parent_pom:
  owner: "yourorg"                              # Your GitHub org/user
  repository: "springboot-test-parent"      # Parent POM repo name
  groupId: "com.example"
  artifactId: "springboot-test-parent"
  version: "2.0.0-SNAPSHOT"
```

**This configuration is used automatically by all migration workflows.**

---

## Running the Migration

### Option A: Automated Workflow

1. Go to **springboot4-migration** repo → **Actions** tab
2. Click **"🚀 Migrate Target Repository"**
3. Enter only the target repository: `your-org/your-app`
4. Parent POM details are **automatically loaded** from `config/parent-pom-config.yml`
5. Workflow:
   - Clones target repo
   - Applies migration rules
   - Runs tests
   - Creates PR with changes

---

### Option B: Copilot-Based Workflow (Recommended for GitHub Packages)

1. Go to **springboot4-migration** repo → **Actions** tab
2. Click **"🚀 Migrate Target Repository"**
3. Click **"Run workflow"**
4. Fill in:
   - **Target repository:** `your-org/your-app` (full name with owner)
   - **Target branch:** `main`
   - Other options as needed
5. Click **"Run workflow"**

The workflow will:
1. Clone the target repository
2. Run all migration phases
3. Push a migration branch to the target repo
4. Create a draft PR on the target repo with a detailed summary

**Option B: Copilot-Based Workflow** (Recommended for GitHub Packages)

1. Go to **Actions** → **"Copilot Migration Trigger"**
2. Enter only the target repository: `your-org/your-app`
3. Parent POM details are **automatically loaded** from `config/parent-pom-config.yml`
4. Workflow creates an issue on the target repo with:
   - Full migration playbook
   - Maven settings template pre-configured with your parent POM URL
   - Parent POM coordinates (groupId, artifactId, version)
5. Copilot agent:
   - Applies migration rules
   - Creates temporary `~/.m2/settings.xml` in runner with your GitHub Packages configuration
   - Resolves parent POM from GitHub Packages using `GITHUB_TOKEN`
   - Compiles application successfully ✅
6. Review the changes and create a PR

**How Parent POM is Resolved:**
- Agent creates temporary `~/.m2/settings.xml` pointing to: `https://maven.pkg.github.com/{owner}/{repository}`
- Maven uses `GITHUB_TOKEN` (auto-available in GitHub Actions)
- Parent POM downloaded automatically
- Compilation succeeds without manual configuration

**No Manual Input Required** - All parent POM details come from `config/parent-pom-config.yml`

### Step 6: Review the PR on the Target Repo

Go to the target repository → Pull Requests → Review the migration PR.

## Running Multiple Migrations

You can trigger the workflow multiple times for different repos simultaneously:

```
Run 1: target_repository = "your-org/user-service"
Run 2: target_repository = "your-org/order-service"
Run 3: target_repository = "your-org/payment-service"
```

Each creates an independent PR on its target repo.

## Customization

Edit `scripts/migrate.sh` to customize:
- `SPRING_BOOT_VERSION` — target version
- `JAVA_VERSION` — target JDK
- `DOCKER_BASE_IMAGE` — Docker base image
- Add organization-specific rules (internal library renames, custom property mappings, etc.)

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Resource not accessible by integration" | Token doesn't have write access to target repo. Check PAT/App permissions. |
| "Compile failed at Phase 1" | Target repo may need manual build file fixes. Check the workflow logs. |
| "OpenRewrite failed" | Some recipes may not apply cleanly. The PR will still be created with mechanical changes. |
| "No changes detected" | Target repo may already be migrated or not match expected patterns. |
