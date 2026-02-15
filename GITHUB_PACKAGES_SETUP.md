# GitHub Packages Configuration for Parent POM Resolution

## Overview

This guide explains how the GitHub Copilot agent will resolve your parent POM from GitHub Packages and successfully compile the migrated application.

---

## How It Works

### 1. Parent POM Must Be Published to GitHub Packages

**First, publish your parent POM:**

```bash
# In your parent POM repository (springboot-test-parent)
cd springboot-test-parent

# Build and publish to GitHub Packages
mvn clean deploy
```

**Your parent POM `pom.xml` needs distributionManagement:**

```xml
<project>
    <!-- ... -->
    
    <distributionManagement>
        <repository>
            <id>github</id>
            <name>GitHub Packages</name>
            <url>https://maven.pkg.github.com/OWNER/REPOSITORY</url>
        </repository>
    </distributionManagement>
    
    <!-- ... -->
</project>
```

Replace:
- `OWNER`: Your GitHub organization or username (e.g., `yourorg`)
- `REPOSITORY`: Repository name (e.g., `springboot-test-parent`)

**Authentication for publishing** (in `~/.m2/settings.xml`):

```xml
<settings>
    <servers>
        <server>
            <id>github</id>
            <username>YOUR_GITHUB_USERNAME</username>
            <password>ghp_YOUR_PERSONAL_ACCESS_TOKEN</password>
        </server>
    </servers>
</settings>
```

Token needs: `write:packages` permission

---

### 2. Migration Workflow Creates `.mvn/settings.xml`

When the GitHub Copilot agent runs the migration:

**Step 1: Apply Rule 3.2.1** (from migration-playbook.md)
- Agent creates `.mvn/settings.xml` in the target repository
- Configures GitHub Packages as Maven repository
- Uses `GITHUB_TOKEN` for authentication

**File created: `.mvn/settings.xml`**

```xml
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0">
    <servers>
        <server>
            <id>github</id>
            <username>${env.GITHUB_ACTOR}</username>
            <password>${env.GITHUB_TOKEN}</password>
        </server>
    </servers>
    
    <profiles>
        <profile>
            <id>github-packages</id>
            <repositories>
                <repository>
                    <id>github</id>
                    <url>https://maven.pkg.github.com/yourorg/springboot-test-parent</url>
                    <releases><enabled>true</enabled></releases>
                    <snapshots>
                        <enabled>true</enabled>
                        <updatePolicy>always</updatePolicy>
                    </snapshots>
                </repository>
            </repositories>
        </profile>
    </profiles>
    
    <activeProfiles>
        <activeProfile>github-packages</activeProfile>
    </activeProfiles>
</settings>
```

**Step 2: Maven Automatically Uses `.mvn/settings.xml`**
- Maven looks for `.mvn/settings.xml` in project root
- Merges with user's `~/.m2/settings.xml`
- GitHub Actions provides `GITHUB_TOKEN` automatically

**Step 3: Compilation Succeeds**
```bash
mvn clean compile -DskipTests
# Maven downloads parent POM from GitHub Packages
# ✅ BUILD SUCCESS
```

---

## Configuration Steps

### One-Time Setup: Configure Parent POM Details

**Edit `config/parent-pom-config.yml`** in the migration repository:

```yaml
parent_pom:
  owner: "yourorg"                              # Your GitHub organization
  repository: "springboot-test-parent"      # Parent POM repository
  groupId: "com.example"
  artifactId: "springboot-test-parent"
  version: "2.0.0-SNAPSHOT"
```

**Commit and push:**
```bash
git add config/parent-pom-config.yml
git commit -m "Configure parent POM for organization"
git push
```

---

### For Copilot Workflow (Automated)

The workflow now automatically reads from `config/parent-pom-config.yml`:

**When you run the workflow:**
1. Go to **Actions** → **"Copilot Migration Trigger"**
2. Enter only the target repository: `yourorg/myapp`
3. Parent POM details are **automatically loaded** from config file
4. Workflow creates issue with pre-configured Maven settings
5. Copilot agent applies migration
6. Agent creates `.mvn/settings.xml` pointing to your GitHub Packages URL
7. Agent compiles successfully ✅

**No manual input needed** - everything comes from the config file!

---

## Verification

### Test Parent POM Resolution Locally

```bash
# Navigate to a target project
cd target-app

# Create .mvn/settings.xml (copy from config/maven-settings-github-packages.xml)
mkdir -p .mvn
cp ../springboot4-migration/config/maven-settings-github-packages.xml .mvn/settings.xml

# Update URL in settings.xml
sed -i 's|OWNER/REPOSITORY|yourorg/springboot-test-parent|g' .mvn/settings.xml

# Set environment variables
export GITHUB_ACTOR="your-username"
export GITHUB_TOKEN="ghp_your_token_here"

# Test parent POM resolution
mvn dependency:get -Dartifact=com.example:springboot-test-parent:2.0.0-SNAPSHOT:pom

# Expected output:
# Downloaded from github: https://maven.pkg.github.com/yourorg/springboot-test-parent/...
# ✅ BUILD SUCCESS
```

---

## GitHub Actions Integration

### In Target Repository's CI/CD

After migration, your target repository's CI/CD workflows need GitHub Packages access:

**Example: `.github/workflows/build.yml`**

```yaml
name: Build
on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Java 25
        uses: actions/setup-java@v4
        with:
          java-version: '25'
          distribution: 'temurin'
          
      - name: Build with Maven
        env:
          GITHUB_TOKEN: ${{ secrets.MIGRATION_PAT }}
          GITHUB_ACTOR: ${{ github.actor }}
        run: mvn clean verify
```

**Key points:**
- ✅ `GITHUB_TOKEN` is automatically available
- ✅ `GITHUB_ACTOR` is set from `github.actor` context
- ✅ `.mvn/settings.xml` created by migration uses these variables
- ✅ Maven resolves parent POM from GitHub Packages

---

## Troubleshooting

### Issue: "Could not resolve parent POM"

**Check:**
1. Parent POM is published to GitHub Packages
2. `.mvn/settings.xml` exists
3. `GITHUB_TOKEN` environment variable is set
4. Token has `read:packages` permission

**Solution:**
```bash
# Verify token has packages permission
gh auth status

# Refresh token if needed
gh auth refresh -s read:packages

# Test parent POM download
export GITHUB_TOKEN=$(gh auth token)
mvn dependency:get -Dartifact=com.example:springboot-test-parent:2.0.0-SNAPSHOT:pom
```

### Issue: "401 Unauthorized" from GitHub Packages

**Cause:** Token doesn't have `read:packages` permission

**Solution:**
```bash
# Refresh with packages scope
gh auth refresh -s read:packages -s write:packages

# Or create new token with packages permissions
gh auth login --scopes "read:packages,write:packages"
```

### Issue: Parent POM Not Found in GitHub Packages

**Verify it's published:**
```bash
# List packages in your org
gh api orgs/YOURORG/packages

# Or check specific package
gh api orgs/YOURORG/packages/maven/springboot-test-parent
```

**Publish it if missing:**
```bash
cd springboot-test-parent
mvn clean deploy
```

---

## Summary

### ✅ What's Configured Now:

1. **Copilot Workflow Updated** (`.github/workflows/copilot-migrate-repo.yml`)
   - Takes parent POM owner/package as input
   - Creates Maven settings template in migration issue
   - Instructs agent to create `.mvn/settings.xml`

2. **Migration Playbook Updated** (`migration-playbook.md`)
   - **Rule 3.2.1**: Create `.mvn/settings.xml` for GitHub Packages
   - **Rule 18.1**: Enhanced compilation check with GitHub Packages support

3. **Template Created** (`config/maven-settings-github-packages.xml`)
   - Ready-to-use Maven settings
   - Uses environment variables for authentication
   - Works in GitHub Actions automatically

4. **Documentation Updated**:
   - `PRE_MIGRATION_CHECKLIST.md`: GitHub Packages as Option A
   - `config/copilot-instructions.md`: Setup instructions

### ✅ How Agent Will Compile:

```
1. Agent reads Rule 3.2.1 from migration playbook
2. Agent creates .mvn/settings.xml pointing to GitHub Packages
3. Agent runs: mvn clean compile -DskipTests
4. Maven uses GITHUB_TOKEN (auto-available in GitHub)
5. Maven downloads parent POM from GitHub Packages
6. Compilation succeeds ✅
```

### 📋 Your Checklist:

- [ ] **One-Time Setup**: Edit `config/parent-pom-config.yml` with your org's details
- [ ] Commit and push the config file to migration repo
- [ ] Publish parent POM to GitHub Packages: `mvn deploy`
- [ ] Verify it's accessible: `gh api orgs/YOURORG/packages/maven/springboot-test-parent`
- [ ] Test workflow on a sample repository (only enter target repo name)
- [ ] Verify agent creates `.mvn/settings.xml` correctly
- [ ] Confirm compilation succeeds in agent's environment

---

**Result**: GitHub Copilot agent can now compile your application by resolving the parent POM from GitHub Packages, using configuration from `config/parent-pom-config.yml`! 🎉
