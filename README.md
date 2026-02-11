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
│       └── migrate-target-repo.yml     # The main workflow
├── scripts/
│   ├── migrate.sh                      # Mechanical migration script
│   ├── validate.sh                     # Post-migration validation
│   └── generate-pr-body.sh            # PR description generator
├── config/
│   ├── openrewrite-init.gradle        # Gradle OpenRewrite init script
│   └── copilot-instructions.md        # Copilot instructions (copied to target)
├── migration-playbook.md              # Full playbook reference
└── README.md                          # This file
```

## Setup Instructions

### Step 1: Create the Migration Repository

```bash
# Create the repo on GitHub (or via UI)
gh repo create YOUR_ORG/springboot4-migration --private --clone
cd springboot4-migration
```

### Step 2: Create a Personal Access Token (PAT) or GitHub App

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

### Step 3: Add the Secret to the Migration Repo

Go to **springboot4-migration** repo → Settings → Secrets and Variables → Actions:

- For PAT: Add secret named `TARGET_REPO_TOKEN` with the PAT value
- For GitHub App: Add secrets `APP_ID` and `APP_PRIVATE_KEY`

### Step 4: Copy All Files Into the Repo

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

### Step 5: Run the Migration

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
