#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# migrate.sh — Automated Migration: Java 21/Spring Boot 3 → Java 25/Spring Boot 4
# ══════════════════════════════════════════════════════════════════════════════
#
# USAGE:
#   chmod +x migrate.sh
#   ./migrate.sh                    # Run all phases
#   ./migrate.sh --phase 1          # Run only Phase 1
#   ./migrate.sh --phase 1-3        # Run Phases 1 through 3
#   ./migrate.sh --dry-run          # Preview changes without applying
#   ./migrate.sh --report-only      # Only scan and report issues
#
# PREREQUISITES:
#   - Git repository (creates migration branch automatically)
#   - Java 25 JDK installed and on PATH
#   - Maven or Gradle project
#   - sed, grep, find (standard unix tools)
#
# ══════════════════════════════════════════════════════════════════════════════

set -uo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
# Customize these for your organization

SPRING_BOOT_VERSION="4.0.0"
JAVA_VERSION="25"
GRADLE_MIN_VERSION="8.14"
DOCKER_BASE_IMAGE="eclipse-temurin:25-jre-noble"
MIGRATION_BRANCH="feat/migrate-springboot4-java25"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Counters
TOTAL_CHANGES=0
TOTAL_FILES=0
TOTAL_WARNINGS=0
PHASE_CHANGES=0

# ── Argument Parsing ──────────────────────────────────────────────────────────

DRY_RUN=false
REPORT_ONLY=false
PHASE_START=1
PHASE_END=7
BUILD_TOOL=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)      DRY_RUN=true; shift ;;
        --report-only)  REPORT_ONLY=true; shift ;;
        --phase)
            if [[ "$2" == *-* ]]; then
                PHASE_START="${2%-*}"
                PHASE_END="${2#*-}"
            else
                PHASE_START="$2"
                PHASE_END="$2"
            fi
            shift 2 ;;
        --help|-h)
            head -20 "$0" | tail -15
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Utility Functions ─────────────────────────────────────────────────────────

log_header() {
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
}

log_phase() {
    echo ""
    echo -e "${CYAN}┌──────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC} ${BOLD}PHASE $1: $2${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────────────┘${NC}"
    PHASE_CHANGES=0
}

log_rule() {
    echo -e "  ${YELLOW}→${NC} Rule $1: $2"
}

log_change() {
    echo -e "    ${GREEN}✔${NC} $1"
    ((TOTAL_CHANGES++)) || true
    ((PHASE_CHANGES++)) || true
}

log_skip() {
    echo -e "    ${YELLOW}⊘${NC} $1 (skipped — not found)"
}

log_warn() {
    echo -e "    ${RED}⚠${NC} $1"
    ((TOTAL_WARNINGS++)) || true
}

log_info() {
    echo -e "    ${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "  ${GREEN}✔ $1${NC}"
}

log_fail() {
    echo -e "  ${RED}✘ $1${NC}"
}

# Safe sed that works on both macOS (BSD) and Linux (GNU)
safe_sed() {
    local pattern="$1"
    local file="$2"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "$pattern" "$file"
    else
        sed -i "$pattern" "$file"
    fi
}

# Find and replace across files with reporting
find_replace() {
    local description="$1"
    local find_pattern="$2"
    local replace_pattern="$3"
    local file_glob="$4"
    local count=0

    if $DRY_RUN || $REPORT_ONLY; then
        count=$(grep -rl "$find_pattern" --include="$file_glob" src/ 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$count" -gt 0 ]]; then
            if $DRY_RUN; then
                echo -e "    ${YELLOW}[DRY-RUN]${NC} Would change $count file(s): $description"
            else
                echo -e "    ${YELLOW}[REPORT]${NC} Found in $count file(s): $description"
            fi
            ((TOTAL_CHANGES+=count)) || true
            ((PHASE_CHANGES+=count)) || true
        fi
        return
    fi

    local files
    files=$(grep -rl "$find_pattern" --include="$file_glob" src/ 2>/dev/null || true)
    if [[ -n "$files" ]]; then
        for file in $files; do
            safe_sed "s|${find_pattern}|${replace_pattern}|g" "$file"
            ((count++)) || true
        done
        log_change "$description ($count file(s))"
        ((TOTAL_FILES+=count)) || true
    else
        log_skip "$description"
    fi
}

# Find and replace in a specific file
replace_in_file() {
    local description="$1"
    local find_pattern="$2"
    local replace_pattern="$3"
    local file="$4"

    if [[ ! -f "$file" ]]; then
        log_skip "$description — file not found: $file"
        return
    fi

    if grep -q "$find_pattern" "$file" 2>/dev/null; then
        if $DRY_RUN || $REPORT_ONLY; then
            echo -e "    ${YELLOW}[$(if $DRY_RUN; then echo DRY-RUN; else echo REPORT; fi)]${NC} Would change: $description in $file"
            ((TOTAL_CHANGES++)) || true
            ((PHASE_CHANGES++)) || true
        else
            safe_sed "s|${find_pattern}|${replace_pattern}|g" "$file"
            log_change "$description in $file"
        fi
    else
        log_skip "$description in $file"
    fi
}

# Detect build tool
detect_build_tool() {
    if [[ -f "pom.xml" ]]; then
        BUILD_TOOL="maven"
    elif [[ -f "build.gradle" ]] || [[ -f "build.gradle.kts" ]]; then
        BUILD_TOOL="gradle"
    else
        echo -e "${RED}ERROR: No pom.xml or build.gradle found. Run from project root.${NC}"
        exit 1
    fi
    log_info "Detected build tool: $BUILD_TOOL"
}

# Compile gate — stops migration if compilation fails
compile_gate() {
    local phase_name="$1"

    if $DRY_RUN || $REPORT_ONLY; then
        echo -e "  ${YELLOW}[$(if $DRY_RUN; then echo DRY-RUN; else echo REPORT; fi)]${NC} Would run compile gate: $phase_name"
        return
    fi

    echo ""
    echo -e "  ${CYAN}Compile gate: $phase_name${NC}"

    local compile_cmd
    if [[ "$BUILD_TOOL" == "maven" ]]; then
        compile_cmd="mvn clean compile -DskipTests -q"
    else
        compile_cmd="./gradlew clean compileJava -q"
    fi

    if $compile_cmd 2>/dev/null; then
        log_success "Compilation passed after $phase_name ($PHASE_CHANGES changes)"
    else
        log_fail "Compilation FAILED after $phase_name"
        echo -e "  ${RED}Fix compilation errors before proceeding.${NC}"
        echo -e "  ${RED}Run: $compile_cmd (without -q) to see errors.${NC}"
        echo -e "  ${YELLOW}Changes so far have been applied. Fix errors and re-run: ./migrate.sh --phase $((${phase_name//[!0-9]/}+1))-7${NC}"
        exit 1
    fi
}

# Test gate
test_gate() {
    if $DRY_RUN || $REPORT_ONLY; then
        echo -e "  ${YELLOW}[$(if $DRY_RUN; then echo DRY-RUN; else echo REPORT; fi)]${NC} Would run test suite"
        return
    fi

    echo ""
    echo -e "  ${CYAN}Running test suite...${NC}"

    local test_cmd
    if [[ "$BUILD_TOOL" == "maven" ]]; then
        test_cmd="mvn test -q"
    else
        test_cmd="./gradlew test -q"
    fi

    if $test_cmd 2>/dev/null; then
        log_success "All tests passed"
    else
        log_fail "Some tests FAILED"
        echo -e "  ${YELLOW}Review test failures. Common causes:${NC}"
        echo -e "    - Missing test starters (spring-boot-starter-*-test)"
        echo -e "    - @MockBean not replaced with @MockitoBean"
        echo -e "    - Jackson serialization changes"
        echo -e "    - Hibernate fetch behavior differences"
    fi
}

# ── Pre-flight Checks ────────────────────────────────────────────────────────

preflight() {
    log_header "PRE-FLIGHT CHECKS"

    # Check we're in a git repo
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        log_success "Git repository detected"
    else
        log_warn "Not a git repository — no backup branch will be created"
    fi

    # Check Java version
    if command -v java &>/dev/null; then
        local java_ver
        java_ver=$(java -version 2>&1 | head -1 | awk -F '"' '{print $2}' | cut -d. -f1)
        if [[ "$java_ver" -ge 25 ]]; then
            log_success "Java $java_ver detected"
        else
            log_warn "Java $java_ver detected — Java 25+ recommended (migration will proceed)"
        fi
    else
        log_warn "Java not found on PATH"
    fi

    # Detect build tool
    detect_build_tool

    # Check for uncommitted changes
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
            log_warn "Uncommitted changes detected — commit or stash before migrating"
            if ! $DRY_RUN && ! $REPORT_ONLY; then
                echo -e "  ${YELLOW}Continue anyway? (y/N)${NC}"
                read -r response
                if [[ "$response" != "y" && "$response" != "Y" ]]; then
                    echo "Aborted."
                    exit 0
                fi
            fi
        fi
    fi

    # Create migration branch
    if git rev-parse --is-inside-work-tree &>/dev/null && ! $DRY_RUN && ! $REPORT_ONLY; then
        local current_branch
        current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
        if [[ "$current_branch" != "$MIGRATION_BRANCH" ]]; then
            echo -e "  ${CYAN}Creating migration branch: $MIGRATION_BRANCH${NC}"
            git checkout -b "$MIGRATION_BRANCH" 2>/dev/null || git checkout "$MIGRATION_BRANCH" 2>/dev/null || true
        fi
        log_success "On branch: $(git branch --show-current)"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 1: BUILD FILES
# ══════════════════════════════════════════════════════════════════════════════

phase_1_build_files() {
    log_phase "1" "BUILD FILES"

    if [[ "$BUILD_TOOL" == "maven" ]]; then
        # ── Rule 1.1: Java version ────────────────────────────────
        log_rule "1.1" "Update Java version in pom.xml"
        replace_in_file "java.version 21→25" \
            "<java.version>21<\/java.version>" \
            "<java.version>25<\/java.version>" \
            "pom.xml"
        replace_in_file "maven.compiler.source 21→25" \
            "<maven.compiler.source>21<\/maven.compiler.source>" \
            "<maven.compiler.source>25<\/maven.compiler.source>" \
            "pom.xml"
        replace_in_file "maven.compiler.target 21→25" \
            "<maven.compiler.target>21<\/maven.compiler.target>" \
            "<maven.compiler.target>25<\/maven.compiler.target>" \
            "pom.xml"

        # ── Rule 3.1: Custom Parent Library ──────────────────────
        log_rule "3.1" "Update Custom Parent Library version"
        if grep -q "springboot-test-parent" pom.xml 2>/dev/null; then
            if ! $DRY_RUN && ! $REPORT_ONLY; then
                # Precisely targets your custom artifact and sets version to 7.0.0
                perl -i -0pe "s|(<artifactId>springboot-test-parent</artifactId>\s*<version>).*?(</version>)|\${1}7.0.0\${2}|g" pom.xml
                log_change "Custom Parent → 7.0.0"
            fi
        fi

        # ── Rule 3.2: Spring Boot BOM ─────────────────────────────
        log_rule "3.2" "Update Spring Boot BOM (if used)"
        if grep -q "spring-boot-dependencies" pom.xml 2>/dev/null; then
            if ! $DRY_RUN && ! $REPORT_ONLY; then
                perl -i -0pe "s|(<artifactId>spring-boot-dependencies</artifactId>\s*<version>)3\.\d+\.\d+[^<]*(</version>)|\${1}${SPRING_BOOT_VERSION}\${2}|g" pom.xml
                log_change "Spring Boot BOM → $SPRING_BOOT_VERSION"
            fi
        fi

        # ── Rule 4.1: Starter renames ─────────────────────────────
        log_rule "4.1-4.2" "Rename starters"
        replace_in_file "starter-web → starter-webmvc" \
            "spring-boot-starter-web<" \
            "spring-boot-starter-webmvc<" \
            "pom.xml"
        replace_in_file "starter-aop → starter-aspectj" \
            "spring-boot-starter-aop<" \
            "spring-boot-starter-aspectj<" \
            "pom.xml"

        # ── Rule 4.3: Remove JUnit vintage ────────────────────────
        log_rule "4.3" "Remove JUnit vintage engine"
        if grep -q "junit-vintage-engine" pom.xml 2>/dev/null; then
            if ! $DRY_RUN && ! $REPORT_ONLY; then
                # Remove the entire exclusion block for vintage engine
                perl -i -0pe 's|<exclusion>\s*<groupId>org\.junit\.vintage</groupId>\s*<artifactId>junit-vintage-engine</artifactId>\s*</exclusion>||g' pom.xml
                log_change "Removed junit-vintage-engine exclusion"
            fi
        fi

        # ── Rule 3.4: Remove authorization-server version override ─
        log_rule "3.4" "Remove spring-authorization-server.version override"
        replace_in_file "Remove auth server version property" \
            "<spring-authorization-server.version>[^<]*<\/spring-authorization-server.version>" \
            "" \
            "pom.xml"

        # ── NEW: Force Dependency Refresh ────────────────────────
        log_info "Running forced dependency update and compilation check..."
        
        # ── Rule 4.3: Robust Test Starter Injection ──────────────
        log_rule "4.3" "Injecting missing test starters"

        add_test_starter_if_missing() {
    local main_starter="$1"    # e.g., spring-boot-starter-webmvc
    local test_starter="$2"    # e.g., spring-boot-starter-webmvc-test

    # If main starter exists and test starter missing → add it
    if grep -q "<artifactId>${main_starter}</artifactId>" pom.xml 2>/dev/null; then
        if ! grep -q "<artifactId>${test_starter}</artifactId>" pom.xml 2>/dev/null; then

            if $DRY_RUN || $REPORT_ONLY; then
                echo -e "    ${YELLOW}[$(if $DRY_RUN; then echo DRY-RUN; else echo REPORT; fi)]${NC} Would add ${test_starter}"
                ((TOTAL_CHANGES++)) || true
                ((PHASE_CHANGES++)) || true
                return
            fi

            # Build the dependency block with REAL newlines (no \n text)
            local DEP_BLOCK
            DEP_BLOCK=$(cat <<EOF
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>${test_starter}</artifactId>
            <scope>test</scope>
        </dependency>
EOF
)

            # Ensure there's a <dependencies> section (create one just before </project> if missing)
            if ! grep -q "<dependencies>" pom.xml 2>/dev/null; then
                perl -i -0777 -pe 's|</project>|  <dependencies>\n  </dependencies>\n</project>|s' pom.xml
            fi

            # Insert into the *project* <dependencies> section.
            # If <dependencyManagement> exists, prefer the <dependencies> that comes AFTER </dependencyManagement>.
            DEP_BLOCK_ENV="$DEP_BLOCK" perl -i -0777 -pe '
                my $dep = $ENV{DEP_BLOCK_ENV} // "";
                if ($dep ne "") {
                    if (m|</dependencyManagement>\s*<dependencies\s*>|s) {
                        s|(</dependencyManagement>\s*<dependencies\s*>)|$1\n$dep|s;
                    } else {
                        s|(<dependencies\s*>)|$1\n$dep|s;
                    }
                }
            ' pom.xml

            log_change "Added ${test_starter}"
        fi
    fi
}


        add_test_starter_if_missing "spring-boot-starter-webmvc"   "spring-boot-starter-webmvc-test"
        add_test_starter_if_missing "spring-boot-starter-data-jpa" "spring-boot-starter-data-jpa-test"

        if ! grep -q "jackson-databind" pom.xml; then
        perl -i -0777 -pe 's|(<dependencies[^>]*>)|$1\n        <dependency>\n            <groupId>tools.jackson.core</groupId>\n            <artifactId>jackson-databind</artifactId>\n        </dependency>|g' pom.xml
    fi

    if grep -rq "MockMvc\|@WebMvcTest" src/test/java 2>/dev/null; then
        if ! grep -q "spring-boot-starter-webmvc-test" pom.xml; then
            perl -i -0777 -pe 's|(<dependencies[^>]*>)|$1\n        <dependency>\n            <groupId>org.springframework.boot</groupId>\n            <artifactId>spring-boot-starter-webmvc-test</artifactId>\n            <scope>test</scope>\n        </dependency>|g' pom.xml
        fi
    fi

elif [[ "$BUILD_TOOL" == "gradle" ]]; then
        local gradle_file
        if [[ -f "build.gradle.kts" ]]; then
            gradle_file="build.gradle.kts"
        else
            gradle_file="build.gradle"
        fi

        log_rule "1.2" "Update Java version in $gradle_file"
        replace_in_file "Java 21→25" "JavaVersion.VERSION_21" "JavaVersion.VERSION_25" "$gradle_file"
        replace_in_file "Java toolchain 21→25" "JavaLanguageVersion.of(21)" "JavaLanguageVersion.of(25)" "$gradle_file"

        log_rule "3.3" "Update Spring Boot plugin version"
        if ! $DRY_RUN && ! $REPORT_ONLY; then
            safe_sed "s|org\.springframework\.boot.*version.*['\"]3\.[0-9]*\.[0-9]*['\"]|org.springframework.boot' version '${SPRING_BOOT_VERSION}'|g" "$gradle_file"
            log_change "Spring Boot plugin → $SPRING_BOOT_VERSION"
        fi

        log_rule "4.1-4.2" "Rename starters"
        replace_in_file "starter-web → starter-webmvc" \
            "spring-boot-starter-web'" \
            "spring-boot-starter-webmvc'" \
            "$gradle_file"
        replace_in_file "starter-web → starter-webmvc (double quotes)" \
            'spring-boot-starter-web"' \
            'spring-boot-starter-webmvc"' \
            "$gradle_file"
        replace_in_file "starter-aop → starter-aspectj" \
            "spring-boot-starter-aop" \
            "spring-boot-starter-aspectj" \
            "$gradle_file"
    fi

    # ── Compile gate ──────────────────────────────────────────────
    # compile_gate "Phase 1"
}

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 2: IMPORT REWRITES
# ══════════════════════════════════════════════════════════════════════════════

phase_2_imports() {
    log_phase "2" "IMPORT REWRITES"

    # ── Rule 5.1: Jackson 2 → 3 package renames in Java files ─────
    log_rule "5.1" "Jackson 2 → 3 package renames (com.fasterxml → tools.jackson)"
    find_replace "Jackson databind imports" \
        "com\.fasterxml\.jackson\.databind" \
        "tools.jackson.databind" \
        "*.java"
    find_replace "Jackson core imports" \
        "com\.fasterxml\.jackson\.core" \
        "tools.jackson.core" \
        "*.java"
    find_replace "Jackson datatype imports" \
        "com\.fasterxml\.jackson\.datatype" \
        "tools.jackson.datatype" \
        "*.java"
    find_replace "Jackson dataformat imports" \
        "com\.fasterxml\.jackson\.dataformat" \
        "tools.jackson.dataformat" \
        "*.java"
    find_replace "Jackson module imports" \
        "com\.fasterxml\.jackson\.module" \
        "tools.jackson.module" \
        "*.java"

    # ── Rule 5.1b: Jackson groupId renames in pom.xml ────────────
    log_rule "5.1b" "Jackson 2 → 3 groupId renames in pom.xml"
    find . -name "pom.xml" -not -path "./.git/*" | while read -r pom; do
        if ! $DRY_RUN && ! $REPORT_ONLY; then
            # com.fasterxml.jackson.core → tools.jackson.core
            sed -i 's|<groupId>com\.fasterxml\.jackson\.core</groupId>|<groupId>tools.jackson.core</groupId>|g' "$pom"
            # com.fasterxml.jackson.datatype → tools.jackson.datatype
            sed -i 's|<groupId>com\.fasterxml\.jackson\.datatype</groupId>|<groupId>tools.jackson.datatype</groupId>|g' "$pom"
            # com.fasterxml.jackson.dataformat → tools.jackson.dataformat
            sed -i 's|<groupId>com\.fasterxml\.jackson\.dataformat</groupId>|<groupId>tools.jackson.dataformat</groupId>|g' "$pom"
            # com.fasterxml.jackson.module → tools.jackson.module
            sed -i 's|<groupId>com\.fasterxml\.jackson\.module</groupId>|<groupId>tools.jackson.module</groupId>|g' "$pom"
            # NOTE: com.fasterxml.jackson.core:jackson-annotations stays as-is (unchanged in Jackson 3)
        fi
    done
    log_change "Jackson groupIds updated in pom.xml files"

    # ── Spring Boot 4 autoconfigure package relocations ───────────
    echo "  Fixing Spring Boot 4 JDBC package relocation..."
    find src/ -name "*.java" -exec sed -i 's/org.springframework.boot.autoconfigure.jdbc/org.springframework.boot.jdbc.autoconfigure/g' {} +

    echo "  Fixing Spring Boot 4 Jackson package relocation..."
    find src/ -name "*.java" -exec sed -i 's/org.springframework.boot.autoconfigure.jackson/org.springframework.boot.jackson.autoconfigure/g' {} +
    # ------------------------------

    # ── Rule 5.4: Spring Boot Jackson annotations ─────────────────
    log_rule "5.4" "Spring Boot Jackson annotation renames"
    find_replace "@JsonComponent → @JacksonComponent" \
        "@JsonComponent" "@JacksonComponent" "*.java"
    find_replace "JsonComponent import" \
        "import org\.springframework\.boot\.jackson\.JsonComponent" \
        "import org.springframework.boot.jackson.JacksonComponent" \
        "*.java"
    find_replace "@JsonMixin → @JacksonMixin" \
        "@JsonMixin" "@JacksonMixin" "*.java"
    find_replace "JsonMixin import" \
        "import org\.springframework\.boot\.jackson\.JsonMixin" \
        "import org.springframework.boot.jackson.JacksonMixin" \
        "*.java"

    # ── Rule 5.5: Jackson serializer class renames ────────────────
    log_rule "5.5" "Jackson serializer/deserializer class renames"
    find_replace "JsonObjectSerializer → ObjectValueSerializer" \
        "JsonObjectSerializer" "ObjectValueSerializer" "*.java"
    find_replace "JsonObjectDeserializer → ObjectValueDeserializer" \
        "JsonObjectDeserializer" "ObjectValueDeserializer" "*.java"

    # ── Rule 8.1: MockBean imports ────────────────────────────────
    log_rule "8.1" "MockBean/SpyBean import rewrites"
    find_replace "@MockBean import" \
        "import org\.springframework\.boot\.test\.mock\.mockito\.MockBean" \
        "import org.springframework.test.context.bean.override.mockito.MockitoBean" \
        "*.java"
    find_replace "@SpyBean import" \
        "import org\.springframework\.boot\.test\.mock\.mockito\.SpyBean" \
        "import org.springframework.test.context.bean.override.mockito.MockitoSpyBean" \
        "*.java"
    
    # ── Rule 8.1b: MockBean/SpyBean annotation usage ───────────────
    log_rule "8.1b" "MockBean/SpyBean annotation rewrites"

    find_replace "@MockBean annotation" \
        "@MockBean" \
        "@MockitoBean" \
        "*.java"

    find_replace "@SpyBean annotation" \
        "@SpyBean" \
        "@MockitoSpyBean" \
        "*.java"


    # ── Rule 8.3: JUnit 4 imports ─────────────────────────────────
    log_rule "8.3" "JUnit 4 → Jupiter import rewrites"
    find_replace "JUnit 4 @Test" \
        "import org\.junit\.Test" \
        "import org.junit.jupiter.api.Test" \
        "*.java"
    find_replace "JUnit 4 @Before" \
        "import org\.junit\.Before;" \
        "import org.junit.jupiter.api.BeforeEach;" \
        "*.java"
    find_replace "JUnit 4 @After;" \
        "import org\.junit\.After;" \
        "import org.junit.jupiter.api.AfterEach;" \
        "*.java"
    find_replace "JUnit 4 @BeforeClass" \
        "import org\.junit\.BeforeClass" \
        "import org.junit.jupiter.api.BeforeAll" \
        "*.java"
    find_replace "JUnit 4 @AfterClass" \
        "import org\.junit\.AfterClass" \
        "import org.junit.jupiter.api.AfterAll" \
        "*.java"
    find_replace "JUnit 4 @Ignore" \
        "import org\.junit\.Ignore" \
        "import org.junit.jupiter.api.Disabled" \
        "*.java"
    find_replace "JUnit 4 Assert" \
        "import org\.junit\.Assert" \
        "import org.junit.jupiter.api.Assertions" \
        "*.java"

    # ── Rule 15.1: Null safety imports ────────────────────────────
    log_rule "15.1" "JSR-305 / Spring → JSpecify null safety imports"
    find_replace "javax.annotation.Nullable → JSpecify" \
        "import javax\.annotation\.Nullable" \
        "import org.jspecify.annotations.Nullable" \
        "*.java"
    find_replace "javax.annotation.Nonnull → JSpecify" \
        "import javax\.annotation\.Nonnull" \
        "import org.jspecify.annotations.NonNull" \
        "*.java"
    find_replace "Spring Nullable → JSpecify" \
        "import org\.springframework\.lang\.Nullable" \
        "import org.jspecify.annotations.Nullable" \
        "*.java"
    find_replace "Spring NonNull → JSpecify" \
        "import org\.springframework\.lang\.NonNull" \
        "import org.jspecify.annotations.NonNull" \
        "*.java"

    # ── Test Package Relocations (Covers src/main and src/test) ────
    log_rule "2.3" "Relocating Spring Boot 4 modularized packages"
    
    # 1. Fix MockitoBean imports (moved from boot.test.mock to test.context)
    find src/ -name "*.java" -exec sed -i 's/org.springframework.boot.test.mock.mockito.MockBean/org.springframework.test.context.bean.override.mockito.MockitoBean/g' {} +
    find src/ -name "*.java" -exec sed -i 's/org.springframework.boot.test.mock.mockito.SpyBean/org.springframework.test.context.bean.override.mockito.MockitoSpyBean/g' {} +
    
    # 2. Fix Web Servlet Test packages (Spring Boot 4 modularization)
    #    OLD: org.springframework.boot.test.autoconfigure.web.servlet.*
    #    NEW: org.springframework.boot.webmvc.test.autoconfigure.*
    #    This includes: AutoConfigureMockMvc, WebMvcTest, MockMvcPrint, etc.
    find src/ -name "*.java" -exec sed -i 's/org\.springframework\.boot\.test\.autoconfigure\.web\.servlet/org.springframework.boot.webmvc.test.autoconfigure/g' {} +

    # 3. Fix Web Client Test packages
    #    OLD: org.springframework.boot.test.autoconfigure.web.client.*
    #    NEW: org.springframework.boot.restclient.test.autoconfigure.*
    find src/ -name "*.java" -exec sed -i 's/org\.springframework\.boot\.test\.autoconfigure\.web\.client/org.springframework.boot.restclient.test.autoconfigure/g' {} +

    # 4. Fix Data JPA Test packages
    #    OLD: org.springframework.boot.test.autoconfigure.orm.jpa.*
    #    NEW: org.springframework.boot.data.jpa.test.autoconfigure.*
    find src/ -name "*.java" -exec sed -i 's/org\.springframework\.boot\.test\.autoconfigure\.orm\.jpa/org.springframework.boot.data.jpa.test.autoconfigure/g' {} +

    # 5. Fix Data JDBC Test packages
    #    OLD: org.springframework.boot.test.autoconfigure.data.jdbc.*
    #    NEW: org.springframework.boot.data.jdbc.test.autoconfigure.*
    find src/ -name "*.java" -exec sed -i 's/org\.springframework\.boot\.test\.autoconfigure\.data\.jdbc/org.springframework.boot.data.jdbc.test.autoconfigure/g' {} +

    # 6. Fix Data MongoDB Test packages
    #    OLD: org.springframework.boot.test.autoconfigure.data.mongo.*
    #    NEW: org.springframework.boot.data.mongodb.test.autoconfigure.*
    find src/ -name "*.java" -exec sed -i 's/org\.springframework\.boot\.test\.autoconfigure\.data\.mongo/org.springframework.boot.data.mongodb.test.autoconfigure/g' {} +

    # 7. Fix Data Redis Test packages
    #    OLD: org.springframework.boot.test.autoconfigure.data.redis.*
    #    NEW: org.springframework.boot.data.redis.test.autoconfigure.*
    find src/ -name "*.java" -exec sed -i 's/org\.springframework\.boot\.test\.autoconfigure\.data\.redis/org.springframework.boot.data.redis.test.autoconfigure/g' {} +

    # 8. Fix JSON Test packages
    #    OLD: org.springframework.boot.test.autoconfigure.json.*
    #    NEW: org.springframework.boot.jackson.test.autoconfigure.*
    find src/ -name "*.java" -exec sed -i 's/org\.springframework\.boot\.test\.autoconfigure\.json/org.springframework.boot.jackson.test.autoconfigure/g' {} +

    # 9. Fix WebFlux Test packages
    #    OLD: org.springframework.boot.test.autoconfigure.web.reactive.*
    #    NEW: org.springframework.boot.webflux.test.autoconfigure.*
    find src/ -name "*.java" -exec sed -i 's/org\.springframework\.boot\.test\.autoconfigure\.web\.reactive/org.springframework.boot.webflux.test.autoconfigure/g' {} +

    # 10. Fix production autoconfigure packages (non-test)
    #     OLD: org.springframework.boot.autoconfigure.web.servlet.*
    #     NEW: org.springframework.boot.webmvc.autoconfigure.*
    find src/ -name "*.java" -exec sed -i 's/org\.springframework\.boot\.autoconfigure\.web\.servlet/org.springframework.boot.webmvc.autoconfigure/g' {} +

    #     OLD: org.springframework.boot.autoconfigure.web.reactive.*
    #     NEW: org.springframework.boot.webflux.autoconfigure.*
    find src/ -name "*.java" -exec sed -i 's/org\.springframework\.boot\.autoconfigure\.web\.reactive/org.springframework.boot.webflux.autoconfigure/g' {} +

    #     OLD: org.springframework.boot.autoconfigure.data.jpa.*
    #     NEW: org.springframework.boot.data.jpa.autoconfigure.*
    find src/ -name "*.java" -exec sed -i 's/org\.springframework\.boot\.autoconfigure\.data\.jpa/org.springframework.boot.data.jpa.autoconfigure/g' {} +

    #     OLD: org.springframework.boot.autoconfigure.orm.jpa.*
    #     NEW: org.springframework.boot.jpa.autoconfigure.*
    find src/ -name "*.java" -exec sed -i 's/org\.springframework\.boot\.autoconfigure\.orm\.jpa/org.springframework.boot.jpa.autoconfigure/g' {} +

    #     OLD: org.springframework.boot.autoconfigure.security.servlet.*
    #     NEW: org.springframework.boot.security.autoconfigure.servlet.*
    find src/ -name "*.java" -exec sed -i 's/org\.springframework\.boot\.autoconfigure\.security\.servlet/org.springframework.boot.security.autoconfigure.servlet/g' {} +

    #     OLD: org.springframework.boot.autoconfigure.security.oauth2.*
    #     NEW: org.springframework.boot.security.autoconfigure.oauth2.*
    find src/ -name "*.java" -exec sed -i 's/org\.springframework\.boot\.autoconfigure\.security\.oauth2/org.springframework.boot.security.autoconfigure.oauth2/g' {} +

    # ── Compile gate ──────────────────────────────────────────────
    # compile_gate "Phase 2"
}

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 3: API / ANNOTATION CHANGES
# ══════════════════════════════════════════════════════════════════════════════

phase_3_api_changes() {
    log_phase "3" "API AND ANNOTATION CHANGES"

    # ── Rule 5.4: Annotation renames ──────────────────────────────
    log_rule "5.4" "Jackson annotation usage renames"
    # Already handled in Phase 2 imports; this catches usage in non-import lines

    # ── Rule 8.1: @MockBean → @MockitoBean (usage) ───────────────
    log_rule "8.1" "@MockBean → @MockitoBean annotation usage"
    find_replace "@MockBean → @MockitoBean" \
        "@MockBean" "@MockitoBean" "*.java"
    find_replace "@SpyBean → @MockitoSpyBean" \
        "@SpyBean" "@MockitoSpyBean" "*.java"

    # ── Rule 8.3: JUnit 4 annotation usage ────────────────────────
    log_rule "8.3" "JUnit 4 annotation usage rewrites"
    find_replace "@Before → @BeforeEach" \
        "@Before$" "@BeforeEach" "*.java"
    find_replace "@After → @AfterEach" \
        "@After$" "@AfterEach" "*.java"
    find_replace "@BeforeClass → @BeforeAll" \
        "@BeforeClass" "@BeforeAll" "*.java"
    find_replace "@AfterClass → @AfterAll" \
        "@AfterClass" "@AfterAll" "*.java"
    find_replace "@Ignore → @Disabled" \
        "@Ignore" "@Disabled" "*.java"
    find_replace "Assert. → Assertions." \
        "Assert\." "Assertions." "*.java"

    # ── Rule 6.2: Security API updates ────────────────────────────
    log_rule "6.2" "Spring Security API updates"
    find_replace ".authorizeRequests() → .authorizeHttpRequests()" \
        "\.authorizeRequests()" ".authorizeHttpRequests()" "*.java"
    find_replace ".antMatchers( → .requestMatchers(" \
        "\.antMatchers(" ".requestMatchers(" "*.java"
    find_replace ".mvcMatchers( → .requestMatchers(" \
        "\.mvcMatchers(" ".requestMatchers(" "*.java"

    # ── Rule 11.2: @OptionalParameter → @Nullable ────────────────
    log_rule "11.2" "Actuator @OptionalParameter → @Nullable"
    find_replace "@OptionalParameter → @Nullable" \
        "@OptionalParameter" "@Nullable" "*.java"
    find_replace "OptionalParameter import" \
        "import org\.springframework\.boot\.actuate\.endpoint\.annotation\.OptionalParameter" \
        "import org.jspecify.annotations.Nullable" \
        "*.java"

    # ── Compile gate ──────────────────────────────────────────────
    # compile_gate "Phase 3"
}

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 4: CONFIGURATION PROPERTIES
# ══════════════════════════════════════════════════════════════════════════════

phase_4_properties() {
    log_phase "4" "CONFIGURATION PROPERTIES"

    # ── Rule 9.1: Jackson property renames ────────────────────────
    log_rule "9.1" "Jackson property namespace renames"

    local prop_files
    prop_files=$(find src/main/resources -name "application*.properties" -o -name "application*.yml" 2>/dev/null || true)

    for pf in $prop_files; do
        [[ -z "$pf" ]] && continue
        replace_in_file "spring.jackson.read → spring.jackson.json.read" \
            "spring\.jackson\.read\." "spring.jackson.json.read." "$pf"
        replace_in_file "spring.jackson.write → spring.jackson.json.write" \
            "spring\.jackson\.write\." "spring.jackson.json.write." "$pf"
        replace_in_file "spring.jackson.datetime → spring.jackson.json.datetime" \
            "spring\.jackson\.datetime\." "spring.jackson.json.datetime." "$pf"
    done

    # ── Scan for other known property issues ──────────────────────
    log_rule "9.3" "Scan for MongoDB property renames"
    local mongo_count
    mongo_count=$(grep -r "spring\.data\.mongodb\." src/main/resources/ 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$mongo_count" -gt 0 ]]; then
        log_warn "Found $mongo_count MongoDB properties — review for renames (see Boot 4 migration guide)"
    fi

    log_rule "9.4" "Scan for tracing property renames"
    local tracing_count
    tracing_count=$(grep -r "management\.tracing\.\|management\.zipkin\." src/main/resources/ 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$tracing_count" -gt 0 ]]; then
        log_warn "Found $tracing_count tracing properties — review for renames"
    fi

    log_rule "16.1" "Scan for Undertow properties"
    local undertow_count
    undertow_count=$(grep -r "server\.undertow\." src/main/resources/ 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$undertow_count" -gt 0 ]]; then
        log_warn "Found $undertow_count Undertow properties — MUST REMOVE (Undertow dropped in Boot 4)"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 5: TEST FIXES
# ══════════════════════════════════════════════════════════════════════════════

phase_5_tests() {
    log_phase "5" "TEST SUITE UPDATES"

    log_rule "5.1" "Renaming @MockBean to @MockitoBean"
    # Search the entire src directory to catch MigrateControllerTest.java
    find src/ -name "*.java" -exec sed -i 's/@MockBean/@MockitoBean/g' {} +
    
    log_rule "5.2" "Renaming @SpyBean to @MockitoSpyBean"
    find src/ -name "*.java" -exec sed -i 's/@SpyBean/@MockitoSpyBean/g' {}

    log_rule "5.3" "Cleaning up legacy JUnit 4 references"
    find src/test/java -name "*.java" -exec sed -i 's/org.junit.Test/org.junit.jupiter.api.Test/g' {} +
    find src/test/java -name "*.java" -exec sed -i 's/@Before /@BeforeEach /g' {} +
    find src/test/java -name "*.java" -exec sed -i 's/@After /@AfterEach /g' {} +

    # ── Test starters reminder ────────────────────────────────────
    log_rule "4.3" "Check test starter dependencies"

    if [[ "$BUILD_TOOL" == "maven" ]]; then
        local starters=("security" "webmvc" "webflux" "data-jpa" "data-mongodb" "data-redis" "kafka" "amqp" "actuator" "validation" "cache" "jackson")
        for starter in "${starters[@]}"; do
            if grep -q "spring-boot-starter-${starter}<" pom.xml 2>/dev/null; then
                if ! grep -q "spring-boot-starter-${starter}-test<" pom.xml 2>/dev/null; then
                    log_warn "Missing test starter: spring-boot-starter-${starter}-test (add with <scope>test</scope>)"
                fi
            fi
        done
    elif [[ "$BUILD_TOOL" == "gradle" ]]; then
        local gradle_file
        if [[ -f "build.gradle.kts" ]]; then gradle_file="build.gradle.kts"; else gradle_file="build.gradle"; fi
        local starters=("security" "webmvc" "webflux" "data-jpa" "data-mongodb" "data-redis" "kafka" "amqp" "actuator" "validation" "cache" "jackson")
        for starter in "${starters[@]}"; do
            if grep -q "spring-boot-starter-${starter}" "$gradle_file" 2>/dev/null; then
                if ! grep -q "spring-boot-starter-${starter}-test" "$gradle_file" 2>/dev/null; then
                    log_warn "Missing test starter: spring-boot-starter-${starter}-test (add as testImplementation)"
                fi
            fi
        done
    fi

    # ── JUnit 4 dependency scan ───────────────────────────────────
    log_rule "8.4" "Scan for JUnit 4 dependencies"
    if grep -q "junit:junit" pom.xml 2>/dev/null || grep -q "'junit:junit'" build.gradle* 2>/dev/null; then
        log_warn "JUnit 4 dependency found — REMOVE (JUnit Jupiter is in spring-boot-starter-test)"
    fi

    # ── Run tests ─────────────────────────────────────────────────
    test_gate
}

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 6: DOCKER & DEPLOYMENT
# ══════════════════════════════════════════════════════════════════════════════

phase_6_deployment() {
    log_phase "6" "DOCKER AND DEPLOYMENT"

    # ── Rule 17.1: Dockerfile base image ──────────────────────────
    log_rule "17.1" "Update Docker base images"

    local docker_files
    docker_files=$(find . -name "Dockerfile*" -o -name "docker-compose*.yml" -o -name "docker-compose*.yaml" 2>/dev/null | grep -v node_modules | grep -v .git || true)

    for df in $docker_files; do
        [[ -z "$df" ]] && continue
        replace_in_file "eclipse-temurin:21 → :25" \
            "eclipse-temurin:21" "eclipse-temurin:25" "$df"
        replace_in_file "amazoncorretto:21 → :25" \
            "amazoncorretto:21" "amazoncorretto:25" "$df"
        replace_in_file "openjdk:21 → eclipse-temurin:25" \
            "openjdk:21" "$DOCKER_BASE_IMAGE" "$df"
    done

    # ── Rule 17.4: CI/CD files ────────────────────────────────────
    log_rule "17.4" "Update CI/CD Java version"

    local ci_files
    ci_files=$(find . -path "./.github/workflows/*.yml" -o -name "Jenkinsfile" -o -name ".gitlab-ci.yml" -o -name "azure-pipelines.yml" 2>/dev/null | grep -v node_modules || true)

    for cf in $ci_files; do
        [[ -z "$cf" ]] && continue
        replace_in_file "CI java-version 21→25" \
            "java-version: '21'" "java-version: '25'" "$cf"
        replace_in_file "CI java-version 21→25 (no quotes)" \
            "java-version: 21" "java-version: 25" "$cf"
    done

    # ── Rule 16.2: Executable launch scripts ──────────────────────
    log_rule "16.2" "Scan for executable launch script config"
    if grep -q "<executable>true</executable>" pom.xml 2>/dev/null; then
        log_warn "Found <executable>true</executable> in pom.xml — REMOVE (launch scripts removed in Boot 4)"
    fi

    # ── Rule 2.3: JVM flag cleanup ────────────────────────────────
    log_rule "2.3" "Scan for obsolete JVM flags"
    for df in $docker_files $ci_files; do
        [[ -z "$df" ]] && continue
        if grep -q "UseCompactObjectHeaders" "$df" 2>/dev/null; then
            log_warn "Found -XX:+UseCompactObjectHeaders in $df — remove (default in Java 25)"
        fi
        if grep -q "UseBiasedLocking" "$df" 2>/dev/null; then
            log_warn "Found UseBiasedLocking in $df — remove (deprecated)"
        fi
    done
}

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 7: VALIDATION
# ══════════════════════════════════════════════════════════════════════════════

phase_7_validation() {
    log_phase "7" "VALIDATION"

    echo -e "  ${CYAN}Running migration validation checks...${NC}"
    echo ""

    # Check 1: javax imports
    local javax_count
    javax_count=$(grep -r "import javax\." src/ --include="*.java" 2>/dev/null | grep -v "javax\.annotation\.\|javax\.crypto\.\|javax\.net\.\|javax\.security\.\|javax\.xml\." | wc -l | tr -d ' ')
    if [[ "$javax_count" -gt 0 ]]; then
        log_fail "Found $javax_count javax.* imports (should be jakarta.*)"
        grep -r "import javax\." src/ --include="*.java" 2>/dev/null | grep -v "javax\.annotation\.\|javax\.crypto\.\|javax\.net\.\|javax\.security\.\|javax\.xml\." | head -5
    else
        log_success "No prohibited javax.* imports"
    fi

    # Check 2: Jackson 2 imports in Java files
    local jackson2_count
    jackson2_count=$(grep -r "import com\.fasterxml\.jackson\." src/ --include="*.java" 2>/dev/null | grep -v "annotation" | wc -l | tr -d ' ')
    if [[ "$jackson2_count" -gt 0 ]]; then
        log_fail "Found $jackson2_count Jackson 2 imports in Java files (should be tools.jackson.*)"
        grep -r "import com\.fasterxml\.jackson\." src/ --include="*.java" 2>/dev/null | grep -v "annotation" | head -5
    else
        log_success "No Jackson 2 imports in Java (excluding annotations)"
    fi

    # Check 2b: Jackson 2 groupIds in pom.xml
    local jackson2_pom_count
    jackson2_pom_count=$(grep -r "com\.fasterxml\.jackson\." --include="pom.xml" . 2>/dev/null | grep -v "annotation" | wc -l | tr -d ' ')
    if [[ "$jackson2_pom_count" -gt 0 ]]; then
        log_fail "Found $jackson2_pom_count Jackson 2 groupIds in pom.xml (should be tools.jackson.*)"
        grep -r "com\.fasterxml\.jackson\." --include="pom.xml" . 2>/dev/null | grep -v "annotation" | head -5
    else
        log_success "No Jackson 2 groupIds in pom.xml"
    fi

    # Check 2c: Old Spring Boot test.autoconfigure packages
    local old_test_pkg_count
    old_test_pkg_count=$(grep -r "org\.springframework\.boot\.test\.autoconfigure\.web\.servlet\|org\.springframework\.boot\.test\.autoconfigure\.orm\.jpa\|org\.springframework\.boot\.test\.autoconfigure\.web\.client" src/ --include="*.java" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$old_test_pkg_count" -gt 0 ]]; then
        log_fail "Found $old_test_pkg_count old Spring Boot test autoconfigure packages (need Boot 4 modular packages)"
        grep -r "org\.springframework\.boot\.test\.autoconfigure\.web\.servlet\|org\.springframework\.boot\.test\.autoconfigure\.orm\.jpa" src/ --include="*.java" 2>/dev/null | head -5
    else
        log_success "No old Spring Boot test autoconfigure packages"
    fi

    # Check 2d: Wrong intermediate package (org.springframework.boot.test.web.servlet — doesn't exist)
    local wrong_test_pkg_count
    wrong_test_pkg_count=$(grep -r "org\.springframework\.boot\.test\.web\.servlet" src/ --include="*.java" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$wrong_test_pkg_count" -gt 0 ]]; then
        log_fail "Found $wrong_test_pkg_count references to non-existent org.springframework.boot.test.web.servlet"
        log_warn "  Correct package is: org.springframework.boot.webmvc.test.autoconfigure"
        grep -r "org\.springframework\.boot\.test\.web\.servlet" src/ --include="*.java" 2>/dev/null | head -5
    else
        log_success "No references to non-existent test.web.servlet package"
    fi

    # Check 3: @MockBean / @SpyBean
    local mockbean_count
    mockbean_count=$(grep -r "@MockBean\|@SpyBean" src/ --include="*.java" 2>/dev/null | grep -v "MockitoBean\|MockitoSpyBean\|import" | wc -l | tr -d ' ')
    if [[ "$mockbean_count" -gt 0 ]]; then
        log_fail "Found $mockbean_count @MockBean/@SpyBean usages"
    else
        log_success "No @MockBean/@SpyBean"
    fi

    # Check 4: JUnit 4
    local junit4_count
    junit4_count=$(grep -r "import org\.junit\." src/ --include="*.java" 2>/dev/null | grep -v "jupiter" | wc -l | tr -d ' ')
    if [[ "$junit4_count" -gt 0 ]]; then
        log_fail "Found $junit4_count JUnit 4 imports"
    else
        log_success "No JUnit 4 imports"
    fi

    # Check 5: Old Jackson properties
    local old_props
    old_props=$(grep -r "spring\.jackson\.read\.\|spring\.jackson\.write\.\|spring\.jackson\.datetime\." src/main/resources/ 2>/dev/null | grep -v "json\." | wc -l | tr -d ' ')
    if [[ "$old_props" -gt 0 ]]; then
        log_fail "Found $old_props old Jackson property names (missing .json. segment)"
    else
        log_success "Jackson properties correctly namespaced"
    fi

    # Check 6: Undertow
    local undertow_count
    undertow_count=$(grep -r "undertow" src/ pom.xml build.gradle* 2>/dev/null | grep -iv "comment\|readme\|playbook\|migration" | wc -l | tr -d ' ')
    if [[ "$undertow_count" -gt 0 ]]; then
        log_fail "Found $undertow_count Undertow references (removed in Boot 4)"
    else
        log_success "No Undertow references"
    fi

    # Check 7: WebSecurityConfigurerAdapter
    local wsca_count
    wsca_count=$(grep -r "WebSecurityConfigurerAdapter" src/ --include="*.java" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$wsca_count" -gt 0 ]]; then
        log_fail "Found $wsca_count WebSecurityConfigurerAdapter references"
    else
        log_success "No WebSecurityConfigurerAdapter"
    fi

    # Check 8: Spring Boot version in build
    if [[ "$BUILD_TOOL" == "maven" ]]; then
        if grep -q "4\.0\.0" pom.xml 2>/dev/null; then
            log_success "Spring Boot version is 4.0.0 in pom.xml"
        else
            log_fail "Spring Boot version not set to 4.0.0 in pom.xml"
        fi
    fi

    # ── Manual review items ───────────────────────────────────────
    echo ""
    echo -e "  ${YELLOW}Items requiring manual review:${NC}"
    echo -e "    ${YELLOW}⚠${NC} Hibernate merge() return value usage (Rule 7.2)"
    echo -e "    ${YELLOW}⚠${NC} Hibernate fetch behavior changes (Rule 7.3)"
    echo -e "    ${YELLOW}⚠${NC} Custom Jackson serializers/deserializers (Rule 5.6)"
    echo -e "    ${YELLOW}⚠${NC} Spring Security filter chain logic (Rule 6.1)"
    echo -e "    ${YELLOW}⚠${NC} @ConfigurationProperties public field binding (Rule 9.2)"
    echo -e "    ${YELLOW}⚠${NC} Spring Batch metadata persistence (Rule 10.1)"
    echo -e "    ${YELLOW}⚠${NC} java.time serialization compatibility (Rule 2.4)"
    echo -e "    ${YELLOW}⚠${NC} Missing test starters (Rule 4.3)"

    local configprops_public
    configprops_public=$(grep -r "@ConfigurationProperties" src/ --include="*.java" -l 2>/dev/null || true)
    if [[ -n "$configprops_public" ]]; then
        echo ""
        echo -e "  ${YELLOW}@ConfigurationProperties classes to check for public fields:${NC}"
        echo "$configprops_public" | while read -r f; do
            echo -e "    ${YELLOW}→${NC} $f"
        done
    fi

    log_rule "7.2" "Scanning for removed Thread methods (suspend/resume/stop)"
    REMOVED_METHODS=$(grep -rE "\.suspend\(\)|\.resume\(\)|\.stop\(\)" src/main/java | wc -l)
    if [ "$REMOVED_METHODS" -gt 0 ]; then
        log_info "Found $REMOVED_METHODS uses of removed Thread methods. These must be manually rewritten."
        ((TOTAL_WARNINGS += REMOVED_METHODS))
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════

main() {
    log_header "MIGRATION: Java 21/Spring Boot 3 → Java 25/Spring Boot 4"

    if $DRY_RUN; then
        echo -e "${YELLOW}  *** DRY RUN MODE — No files will be modified ***${NC}"
    elif $REPORT_ONLY; then
        echo -e "${YELLOW}  *** REPORT ONLY MODE — Scanning for migration items ***${NC}"
    fi

    echo -e "  Phases: ${PHASE_START} through ${PHASE_END}"
    echo ""

    preflight

    [[ $PHASE_START -le 1 && $PHASE_END -ge 1 ]] && phase_1_build_files
    [[ $PHASE_START -le 2 && $PHASE_END -ge 2 ]] && phase_2_imports
    [[ $PHASE_START -le 3 && $PHASE_END -ge 3 ]] && phase_3_api_changes
    [[ $PHASE_START -le 4 && $PHASE_END -ge 4 ]] && phase_4_properties
    [[ $PHASE_START -le 5 && $PHASE_END -ge 5 ]] && phase_5_tests
    [[ $PHASE_START -le 6 && $PHASE_END -ge 6 ]] && phase_6_deployment
    [[ $PHASE_START -le 7 && $PHASE_END -ge 7 ]] && phase_7_validation

    # ── Summary ───────────────────────────────────────────────────
    log_header "MIGRATION SUMMARY"
    echo -e "  Total changes applied:  ${GREEN}${TOTAL_CHANGES}${NC}"
    echo -e "  Warnings / manual items: ${YELLOW}${TOTAL_WARNINGS}${NC}"
    echo ""

    if ! $DRY_RUN && ! $REPORT_ONLY; then
        echo -e "  ${CYAN}Next steps:${NC}"
        echo -e "    1. Review the warnings above and address manual items"
        echo -e "    2. Run full test suite: $(if [[ $BUILD_TOOL == maven ]]; then echo 'mvn test'; else echo './gradlew test'; fi)"
        echo -e "    3. Start the application and smoke test"
        echo -e "    4. Commit: git add -A && git commit -m 'Migrate to Java 25 + Spring Boot 4'"
        echo ""
        echo -e "  ${CYAN}For deeper automation, run OpenRewrite:${NC}"
        if [[ "$BUILD_TOOL" == "maven" ]]; then
            echo -e "    mvn rewrite:run  (see openrewrite-config.yml)"
        else
            echo -e "    ./gradlew rewriteRun  (see openrewrite-config.yml)"
        fi
    fi
    echo ""
}

main