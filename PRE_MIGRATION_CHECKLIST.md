# Pre-Migration Checklist

Before running the Spring Boot 4 migration workflow on a target repository, ensure these prerequisites are met:

---

## ✅ 1. Parent POM Availability & Configuration

### If Using a Custom Parent POM (e.g., springboot-test-parent):

The migration assumes your parent POM is **already migrated to Spring Boot 4** and available from one of these sources:

#### Option A: GitHub Packages (✅ Recommended for GitHub Copilot Agent)

**Requirements:**
- Parent POM published to GitHub Packages: `https://maven.pkg.github.com/OWNER/REPO`
- Version `2.0.0` (or your migrated version) exists
- Target repositories have GitHub token with `read:packages` permission

**Verification:**
```bash
export GITHUB_ACTOR="your-username"
export GITHUB_TOKEN="ghp_your_token_here"  # or use secrets.GITHUB_TOKEN in Actions

mvn dependency:get \
  -Dartifact=com.example:springboot-test-parent:2.0.0:pom \
  -DremoteRepositories=github::https://maven.pkg.github.com/yourorg/springboot-test-parent
```

**How Agent Will Compile:**
1. Agent creates temporary `~/.m2/settings.xml` with GitHub Packages configuration (Rule 3.2.1)
2. Uses `GITHUB_TOKEN` for authentication (automatically available in GitHub Actions)
3. Maven resolves parent POM from GitHub Packages
4. Compilation succeeds ✅

#### Option B: Maven Repository (Nexus/Artifactory)

**Requirements:**
- Parent POM published to your organization's Maven repository
- Version `2.0.0` exists
- Repository allows anonymous read OR credentials are configured

**Verification:**
```bash
mvn dependency:get \
  -Dartifact=com.example:springboot-test-parent:2.0.0:pom \
  -DremoteRepositories=nexus::https://nexus.yourcompany.com/repository/maven-snapshots/
```

**How Agent Will Compile:**
- ⚠️ **Agent cannot access private Nexus without credentials**
- Agent will skip compilation and document this
- Compilation validated in target repository's CI/CD (which has credentials)

**To enable agent compilation:**
- Configure Nexus to allow anonymous read access for parent POM repository, OR
- Create temporary `~/.m2/settings.xml` during build with Nexus configuration (Rule 3.2.2)

#### Option C: Local .m2 (For Development/Testing Only)

**Requirements:**
- Parent POM installed in local Maven repository: `~/.m2/repository/`
- Run: `mvn install` in your parent POM project

**Usage:**
- ✅ Works for local development
- ❌ Does NOT work for CI/CD or GitHub Copilot agent
- Use for testing migration locally only

### Parent POM Requirements:

Your migrated parent POM must:
- ✅ Inherit from `spring-boot-starter-parent:4.0.0` (or later)
- ✅ Set `<java.version>25</java.version>`
- ✅ Configure `maven.compiler.source/target/release=25`
- ✅ Include `lombok.version=1.18.40+` (for Java 25 support)
- ✅ Configure Maven Toolchains plugin for JDK 25
- ✅ Use modularized starters (e.g., `spring-boot-starter-webmvc` not `spring-boot-starter-web`)

### What the Agent Will Do:

- ✅ **WILL**: Update parent version in child POM: `1.0.0-SNAPSHOT` → `2.0.0`
- ❌ **WON'T**: Create or modify the parent POM file itself
- ❌ **WON'T**: Try to install the parent POM to .m2

---

## ✅ 2. Java 25 Availability

Ensure Java 25 is available in your environment:

**For Local Development:**
```bash
# Check Java version
java -version
# Should show: java version "25.0.1" or later

# Configure Maven Toolchains (optional but recommended)
# Create/update ~/.m2/toolchains.xml
```

**For CI/CD:**
- Ensure your CI environment (GitHub Actions, Jenkins, GitLab CI, etc.) has Java 25 available
- Update CI configuration to use Java 25 before running migration

---

## ✅ 3. Maven/Gradle Version

**Maven:**
- Version 3.9+ required
- Check: `mvn -version`

**Gradle:**
- Version 8.14+ or 9.x required
- Check: `./gradlew --version`

---

## ✅ 4. Repository Structure Check

Before migration, verify your target repository:

### Does NOT Contain Parent POM
```bash
# These should NOT exist in target repo:
# ❌ springboot-test-parent/pom.xml
# ❌ parent-pom/pom.xml
```

If your repository contains a parent POM, either:
1. Split it into a separate repository first, or
2. Adjust the migration playbook to handle combined repositories

### Contains Standard Maven/Gradle Structure
```
✅ pom.xml (or build.gradle)
✅ src/main/java/
✅ src/test/java/
```

---

## ✅ 5. Backup & Branch Strategy

Before running migration:

1. **Create a migration branch:**
   ```bash
   git checkout -b migration/spring-boot-4
   ```

2. **Ensure clean working directory:**
   ```bash
   git status
   # Should show: working tree clean
   ```

3. **Tag current state (optional but recommended):**
   ```bash
   git tag -a pre-migration-sb3 -m "Before Spring Boot 4 migration"
   git push origin pre-migration-sb3
   ```

---

## ✅ 6. Dependency Conflicts Pre-Check

Run dependency analysis before migration:

```bash
# Maven
mvn dependency:tree > dependencies-before.txt
mvn dependency:analyze

# Gradle
./gradlew dependencies > dependencies-before.txt
```

Look for:
- ❌ Explicit Jackson 2 dependencies (should be removed/excluded)
- ❌ JUnit 4 dependencies (should be removed)
- ❌ Incompatible library versions

---

## ✅ 7. Access & Permissions

Ensure you have:

- **GitHub/GitLab Access:**
  - Write access to target repository
  - Permissions to create branches and PRs
  - Valid `MIGRATION_PAT` token (if using GitHub Actions)

- **Maven Repository Access:**
  - Credentials configured in `~/.m2/settings.xml`
  - Network access to your Maven repository (Nexus/Artifactory)

---

## Running the Migration

Once all prerequisites are met:

### Using GitHub Workflow:
```bash
# Trigger via GitHub UI:
# Actions → Copilot Migration Trigger → Run workflow
# Enter: target_repository (e.g., myorg/myapp)
```

### Using Local Command:
```bash
# Clone target repository
git clone <target-repo-url>
cd <target-repo>

# Ensure parent POM is available
mvn dependency:get \
  -Dartifact=com.example:springboot-test-parent:2.0.0:pom \
  -DremoteRepositories=<your-nexus-url>

# Apply migration manually or via Copilot
# Follow migration-playbook.md
```

---

## Post-Migration Validation

After migration completes:

1. **Verify compilation:**
   ```bash
   mvn clean compile -DskipTests
   ```

2. **Run tests:**
   ```bash
   mvn test
   ```

3. **Check dependency tree:**
   ```bash
   mvn dependency:tree > dependencies-after.txt
   diff dependencies-before.txt dependencies-after.txt
   ```

4. **Verify no javax.* imports remain:**
   ```bash
   grep -r "import javax\." src/ --include="*.java"
   # Should return no results (except javax.annotation for null safety)
   ```

5. **Start application:**
   ```bash
   mvn spring-boot:run
   # Or: java -jar target/app.jar
   ```

---

## Common Issues

### "Parent POM not found"

**Problem:** Maven can't resolve the parent POM  
**Solution:**
1. Verify parent POM is published to your Maven repository
2. Check `~/.m2/settings.xml` for correct repository configuration
3. Try: `mvn dependency:get -Dartifact=com.example:springboot-test-parent:2.0.0:pom`

### "Agent Created Parent POM in Repository"

**Problem:** Copilot agent created parent POM files  
**Solution:**
1. Delete the created parent POM files
2. Ensure you're using the latest migration-playbook.md (with external dependency warnings)
3. Re-run migration with updated playbook

### "Compilation fails after migration"

**Problem:** Missing dependencies or API changes  
**Solution:**
1. Check migration-playbook.md for missed rules
2. Verify all test starters are added (Rule 4.3)
3. Check for Jackson 2 → 3 import changes (Rule 5.1)
4. Check for @MockBean → @MockitoBean changes (Rule 8.1)

---

## Need Help?

- Review the full migration playbook: `migration-playbook.md`
- Check Copilot instructions: `.github/copilot-instructions.md`
- Open an issue in the migration repository

---

**Last Updated:** February 2026  
**Migration Playbook Version:** 1.0
