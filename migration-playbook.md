# Migration Playbook: Java 21 + Spring Boot 3 → Java 25 + Spring Boot 4

> **Purpose**: Machine-readable migration playbook for use with GitHub Copilot, Copilot Workspace, or any AI-assisted code transformation tool. Each rule is self-contained with find/replace patterns, AST-level instructions, and validation criteria.
>
> **Usage**: Point Copilot at this file as context when performing migrations. Rules are tagged with priority, scope, and file-pattern globs so agents can filter relevant rules per file.

---

## Table of Contents

- [0. Meta — How to Use This Playbook](#0-meta--how-to-use-this-playbook)
- [1. Build Files](#1-build-files)
- [2. Java Version & Language Features](#2-java-version--language-features)
- [3. Spring Boot Parent & BOM](#3-spring-boot-parent--bom)
- [4. Modularized Starters](#4-modularized-starters)
- [5. Jackson 2 → 3](#5-jackson-2--3)
- [6. Spring Security 6 → 7](#6-spring-security-6--7)
- [7. Hibernate 6 → 7 / JPA](#7-hibernate-6--7--jpa)
- [8. Testing](#8-testing)
- [9. Configuration Properties](#9-configuration-properties)
- [10. Spring Batch 5 → 6](#10-spring-batch-5--6)
- [11. Observability & Actuator](#11-observability--actuator)
- [12. Resilience (New)](#12-resilience-new)
- [13. API Versioning (New)](#13-api-versioning-new)
- [14. HTTP Service Clients (New)](#14-http-service-clients-new)
- [15. Null Safety — JSpecify](#15-null-safety--jspecify)
- [16. Removed Features](#16-removed-features)
- [17. Docker & Deployment](#17-docker--deployment)
- [18. Validation & Smoke Tests](#18-validation--smoke-tests)
- [Appendix A: Full Import Rewrite Map](#appendix-a-full-import-rewrite-map)
- [Appendix B: Property Rename Map](#appendix-b-property-rename-map)
- [Appendix C: OpenRewrite Automation](#appendix-c-openrewrite-automation)

---

## 0. Meta — How to Use This Playbook

### For Copilot / AI Agents

```text
INSTRUCTIONS FOR AI AGENT:
1. Read the entire playbook before making changes.
2. Process rules in order (Section 1 → 18). Dependencies exist between sections.
3. Each rule has:
   - SCOPE: file glob pattern(s) to match
   - PRIORITY: CRITICAL | HIGH | MEDIUM | LOW
   - FIND: pattern to locate (regex or literal)
   - REPLACE: replacement pattern
   - VALIDATE: how to confirm the change is correct
4. Rules marked [CONDITIONAL] only apply if the codebase uses that feature.
5. Rules marked [MANUAL-REVIEW] require human verification after applying.
6. Do NOT apply rules to files under /test/resources/, /generated/, or /build/.
7. After all rules: compile, run tests, report failures.
```

### Execution Order

```text
Phase 1: Build files (Section 1, 3, 4)        — must compile after this phase
Phase 2: Import rewrites (Section 5, 6, 7)    — must compile after this phase
Phase 3: API changes (Section 5–11)            — must compile after this phase
Phase 4: Test changes (Section 8)              — tests must pass after this phase
Phase 5: New features (Section 12–15)          — optional, adopt incrementally
Phase 6: Deployment (Section 16, 17)           — infra changes
Phase 7: Validation (Section 18)               — final checks
```

---

## 1. Build Files

### Rule 1.1 — Maven: Update Java Version

```yaml
scope: "**/pom.xml"
priority: CRITICAL
find: "<java.version>21</java.version>"
replace: "<java.version>25</java.version>"
validate: "mvn -version shows Java 25; mvn compile succeeds"
```

Also check for alternative patterns:

```yaml
find: "<maven.compiler.source>21</maven.compiler.source>"
replace: "<maven.compiler.source>25</maven.compiler.source>"
```

```yaml
find: "<maven.compiler.target>21</maven.compiler.target>"
replace: "<maven.compiler.target>25</maven.compiler.target>"
```

```yaml
find: "<release>21</release>"
replace: "<release>25</release>"
```

### Rule 1.2 — Gradle: Update Java Version

```yaml
scope: "**/build.gradle, **/build.gradle.kts"
priority: CRITICAL
find_regex: "sourceCompatibility\s*=\s*['\"]?(?:JavaVersion\.VERSION_21|21|'21')['\"]?"
replace: "sourceCompatibility = JavaVersion.VERSION_25"
```

```yaml
find_regex: "targetCompatibility\s*=\s*['\"]?(?:JavaVersion\.VERSION_21|21|'21')['\"]?"
replace: "targetCompatibility = JavaVersion.VERSION_25"
```

```yaml
find_regex: "languageVersion\.set\(JavaLanguageVersion\.of\(21\)\)"
replace: "languageVersion.set(JavaLanguageVersion.of(25))"
```

### Rule 1.3 — Gradle: Verify Gradle Version

```yaml
scope: "**/gradle/wrapper/gradle-wrapper.properties"
priority: CRITICAL
condition: "Gradle version must be >= 8.14 or 9.x"
find_regex: "gradle-(\d+\.\d+)"
validate: "extracted version >= 8.14 or >= 9.0"
action: "If version < 8.14, update to latest 8.x or 9.x: ./gradlew wrapper --gradle-version=8.14"
```

### Rule 1.4 — Maven: Verify Maven Version

```yaml
scope: "**/pom.xml, **/.mvn/wrapper/maven-wrapper.properties"
priority: HIGH
condition: "Maven version must be >= 3.9"
validate: "mvn -version shows 3.9+"
```

---

## 2. Java Version & Language Features

### Rule 2.1 — Adopt Unnamed Variables (Optional)

```yaml
scope: "**/*.java"
priority: LOW
description: "Replace unused catch/lambda parameters with _"
find_regex: "catch\s*\(\s*(\w+)\s+(\w+)\s*\)" 
action: "If the caught variable is never referenced in the catch block, replace with: catch (Exception _)"
example_before: "catch (NumberFormatException ex) { log.warn(\"bad input\"); }"
example_after: "catch (NumberFormatException _) { log.warn(\"bad input\"); }"
note: "[MANUAL-REVIEW] Only apply when the variable is truly unused"
```

### Rule 2.2 — Virtual Threads: Remove Pinning Workarounds

```yaml
scope: "**/*.java"
priority: MEDIUM
condition: "Codebase uses virtual threads AND has ReentrantLock workarounds for monitor pinning"
description: "Java 24+ unpins virtual threads from monitors. synchronized blocks no longer pin carrier threads."
action: |
  Review any ReentrantLock replacements that were specifically added to avoid virtual thread pinning.
  These can now be safely reverted back to synchronized if the original intent was pinning avoidance.
note: "[MANUAL-REVIEW] Only revert locks that were explicitly documented as pinning workarounds"
```

### Rule 2.3 — JVM Flags: Update for Java 25

```yaml
scope: "**/Dockerfile, **/docker-compose*.yml, **/*.sh, **/*.env, **/jvm.options, **/JAVA_OPTS"
priority: HIGH
actions:
  - description: "Compact object headers are default — remove explicit flag if present"
    find: "-XX:+UseCompactObjectHeaders"
    replace: ""
  - description: "ZGC generational mode is default — remove explicit flag if present"  
    find: "-XX:+UseZGenerationalGC"
    replace: ""
  - description: "Add dynamic agent flag if runtime agents are used"
    condition: "Application attaches Java agents at runtime (e.g., profilers, APM)"
    action: "Add -XX:+EnableDynamicAgentLoading to JVM flags"
  - description: "Remove deprecated flags"
    find_regex: "-XX:[+-]UseBiasedLocking"
    replace: ""
```

### Rule 2.4 — java.time Serialization Incompatibility

```yaml
scope: "**/*.java"
priority: HIGH
condition: "Application serializes java.time classes (LocalDate, LocalDateTime, etc.) via Java serialization"
description: |
  JDK 25 changed the serialized form of several java.time classes.
  Serialized objects from JDK 21 may not deserialize correctly on JDK 25 and vice versa.
action: |
  1. Identify any use of ObjectInputStream/ObjectOutputStream with java.time types.
  2. Migrate to JSON or another format for cross-version compatibility.
  3. If Java serialization is required, test thoroughly with both JDK versions.
note: "[MANUAL-REVIEW] Critical for applications using distributed caches with Java serialization"
```

---

## 3. Spring Boot Parent & BOM

### Rule 3.1 — Maven: Update Parent POM

```yaml
scope: "**/pom.xml"
priority: CRITICAL
description: |
  This project uses a custom parent POM (spring-boot-mongodb-parent) which itself
  inherits from spring-boot-starter-parent. Update the child POM to reference
  the new parent version that targets Spring Boot 4.0.0.
find_regex: |
  <parent>\s*
    <groupId>com\.example</groupId>\s*
    <artifactId>spring-boot-mongodb-parent</artifactId>\s*
    <version>1\.0\.0-SNAPSHOT</version>
replace: |
  <parent>
    <groupId>com.example</groupId>
    <artifactId>spring-boot-mongodb-parent</artifactId>
    <version>2.0.0-SNAPSHOT</version>
pre_requisite: |
  The parent POM (spring-boot-mongodb-parent:2.0.0-SNAPSHOT) must be installed first:
    mvn install -f <path-to>/spring-boot-mongodb-parent/pom.xml
  The parent POM inherits from spring-boot-starter-parent:4.0.0 and sets:
    - java.version=25
    - maven.compiler.source/target/release=25
    - lombok.version=1.18.40 (with annotationProcessorPaths)
    - Maven Toolchains for JDK 25
validate: "mvn dependency:tree resolves without conflicts"
```

### Rule 3.2 — Parent POM: spring-boot-mongodb-parent Configuration

```yaml
scope: "spring-boot-mongodb-parent/pom.xml"
priority: CRITICAL
description: |
  The custom parent POM must inherit from spring-boot-starter-parent:4.0.0
  and configure Java 25 compilation, Lombok, and toolchains.
find_regex: |
  <parent>\s*
    <groupId>org\.springframework\.boot</groupId>\s*
    <artifactId>spring-boot-starter-parent</artifactId>\s*
    <version>3\.\d+\.\d+</version>
replace: |
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>4.0.0</version>
additional_changes:
  - property: "spring-boot.version" → "4.0.0"
  - property: "java.version" → "25"
  - property: "maven.compiler.source" → "25"
  - property: "maven.compiler.target" → "25"
  - property: "lombok.version" → "1.18.40" (required for Java 25)
  - plugin: maven-compiler-plugin → add Lombok to annotationProcessorPaths
  - plugin: maven-toolchains-plugin → JDK version 25
  - starters: spring-boot-starter-webmvc (replaces spring-boot-starter-web)
  - test starters: spring-boot-starter-webmvc-test, spring-boot-starter-data-mongodb-test
validate: "mvn install on parent succeeds; child project resolves all dependencies"
```

### Rule 3.3 — Gradle: Update Spring Boot Plugin

```yaml
scope: "**/build.gradle, **/build.gradle.kts"
priority: CRITICAL
find_regex: "id\s*['\"]org\.springframework\.boot['\"]\s*version\s*['\"]3\.\d+\.\d+['\"]"
replace: "id 'org.springframework.boot' version '4.0.0'"
```

### Rule 3.4 — Remove spring-authorization-server.version Override

```yaml
scope: "**/pom.xml, **/build.gradle*"
priority: HIGH
condition: "Project overrides spring-authorization-server.version"
find: "spring-authorization-server.version"
action: "Remove this property. Use spring-security.version instead if version override is needed."
```

### Rule 3.5 — Remove Uber-JAR Loader Configuration

```yaml
scope: "**/pom.xml, **/build.gradle*"
priority: HIGH
description: "Classic uber-jar loader has been removed"
action: "Remove any loader implementation configuration from build file (e.g., layout=ZIP, requiresUnpack, etc.)"
find_regex: "<layout>ZIP</layout>|<requiresUnpack>|loader\.implementation"
replace: ""
note: "[MANUAL-REVIEW] Verify build still produces valid executable jar"
```

---

## 4. Modularized Starters

### Rule 4.0 — Quick Migration: Use Classic Starters (Temporary)

```yaml
scope: "**/pom.xml, **/build.gradle*"
priority: HIGH
description: |
  For rapid migration, swap to classic starters first, then migrate to specific starters later.
  This provides Spring Boot 3-like behavior with all auto-configuration classes available.
actions:
  - find: "spring-boot-starter</artifactId>"
    replace: "spring-boot-starter-classic</artifactId>"
    note: "Only for the base starter, not technology-specific starters"
  - find: "spring-boot-starter-test</artifactId>"
    replace: "spring-boot-starter-test-classic</artifactId>"
note: "TEMPORARY — migrate to specific starters when stable"
```

### Rule 4.1 — Rename spring-boot-starter-web to webmvc

```yaml
scope: "**/pom.xml"
priority: HIGH
condition: "Application uses Spring MVC (not WebFlux)"
find: "<artifactId>spring-boot-starter-web</artifactId>"
replace: "<artifactId>spring-boot-starter-webmvc</artifactId>"
```

```yaml
scope: "**/build.gradle*"
find_regex: "['\"]org\.springframework\.boot:spring-boot-starter-web['\"]"
replace: "'org.springframework.boot:spring-boot-starter-webmvc'"
```

### Rule 4.2 — Rename spring-boot-starter-aop

```yaml
scope: "**/pom.xml, **/build.gradle*"
priority: HIGH
find: "spring-boot-starter-aop"
replace: "spring-boot-starter-aspectj"
```

### Rule 4.3 — Add Test Starters

```yaml
scope: "**/pom.xml, **/build.gradle*"
priority: HIGH
description: |
  Spring Boot 4 requires explicit test starters for technology-specific test support.
  Without these, annotations like @WithMockUser, @DataJpaTest slice configs, etc. may not work.
actions: |
  For each technology starter in your dependencies, add the corresponding test starter
  with <scope>test</scope> (Maven) or testImplementation (Gradle):
  
  spring-boot-starter-security       → ADD spring-boot-starter-security-test
  spring-boot-starter-webmvc         → ADD spring-boot-starter-webmvc-test
  spring-boot-starter-webflux        → ADD spring-boot-starter-webflux-test
  spring-boot-starter-data-jpa       → ADD spring-boot-starter-data-jpa-test
  spring-boot-starter-data-mongodb   → ADD spring-boot-starter-data-mongodb-test
  spring-boot-starter-data-redis     → ADD spring-boot-starter-data-redis-test
  spring-boot-starter-data-r2dbc     → ADD spring-boot-starter-data-r2dbc-test
  spring-boot-starter-jdbc           → ADD spring-boot-starter-jdbc-test
  spring-boot-starter-graphql        → ADD spring-boot-starter-graphql-test
  spring-boot-starter-kafka          → ADD spring-boot-starter-kafka-test
  spring-boot-starter-amqp           → ADD spring-boot-starter-amqp-test
  spring-boot-starter-cache          → ADD spring-boot-starter-cache-test
  spring-boot-starter-jackson        → ADD spring-boot-starter-jackson-test
  spring-boot-starter-validation     → ADD spring-boot-starter-validation-test
  spring-boot-starter-actuator       → ADD spring-boot-starter-actuator-test
```

### Rule 4.4 — Spring Batch Starter Split

```yaml
scope: "**/pom.xml, **/build.gradle*"
priority: HIGH
condition: "Application uses Spring Batch"
description: |
  Spring Batch now operates in-memory by default (spring-boot-starter-batch).
  To persist batch metadata to a database, use spring-boot-starter-batch-jdbc.
action: |
  If your application relies on batch job metadata in a database:
    find: "spring-boot-starter-batch"
    replace: "spring-boot-starter-batch-jdbc"
  If in-memory batch execution is acceptable:
    No change needed.
note: "[MANUAL-REVIEW] Verify batch job restart/recovery behavior"
```

### Rule 4.5 — Full Starter Rename Map

```yaml
scope: "**/pom.xml, **/build.gradle*"
priority: MEDIUM
description: "Additional starters that have been renamed or split"
renames:
  spring-boot-starter-web: "spring-boot-starter-webmvc (for MVC apps)"
  spring-boot-starter-aop: "spring-boot-starter-aspectj"
  spring-boot-starter-batch: "spring-boot-starter-batch (in-memory) OR spring-boot-starter-batch-jdbc (database)"
note: "Most other starters retain their names but now have dedicated test companions"
```

---

## 5. Jackson 2 → 3

### Rule 5.1 — Package Rename: com.fasterxml.jackson → tools.jackson

```yaml
scope: "**/*.java"
priority: CRITICAL
description: "Jackson 3 relocated most packages. Exception: jackson-annotations stays under com.fasterxml.jackson.annotation"
rewrites:
  - find: "import com.fasterxml.jackson.databind."
    replace: "import tools.jackson.databind."
  - find: "import com.fasterxml.jackson.core."
    replace: "import tools.jackson.core."
  - find: "import com.fasterxml.jackson.datatype."
    replace: "import tools.jackson.datatype."
  - find: "import com.fasterxml.jackson.dataformat."
    replace: "import tools.jackson.dataformat."
  - find: "import com.fasterxml.jackson.module."
    replace: "import tools.jackson.module."
DO_NOT_CHANGE:
  - "import com.fasterxml.jackson.annotation.*"  # Annotations stay in old package
validate: "No remaining com.fasterxml.jackson imports (except annotation package)"
```

### Rule 5.2 — Maven/Gradle: Jackson Group ID

```yaml
scope: "**/pom.xml, **/build.gradle*"
priority: CRITICAL
description: "Update Jackson artifact group IDs"
rewrites:
  - find: "<groupId>com.fasterxml.jackson.core</groupId>"
    replace: "<groupId>tools.jackson.core</groupId>"
    exception: "jackson-annotations stays under com.fasterxml.jackson.core"
  - find: "<groupId>com.fasterxml.jackson.datatype</groupId>"
    replace: "<groupId>tools.jackson.datatype</groupId>"
  - find: "<groupId>com.fasterxml.jackson.dataformat</groupId>"
    replace: "<groupId>tools.jackson.dataformat</groupId>"
  - find: "<groupId>com.fasterxml.jackson.module</groupId>"
    replace: "<groupId>tools.jackson.module</groupId>"
note: |
  Spring Boot 4 manages Jackson 3 versions. If you have explicit version overrides
  for Jackson 2, remove them and let Boot's BOM manage versions.
```

### Rule 5.3 — ObjectMapper → JsonMapper

```yaml
scope: "**/*.java"
priority: HIGH
description: "Jackson 3 prefers JsonMapper with builder pattern over ObjectMapper"
find_regex: "new ObjectMapper\(\)"
replace: "JsonMapper.builder().build()"
additional:
  - find: "ObjectMapper mapper"
    replace: "JsonMapper mapper"
  - find: "import tools.jackson.databind.ObjectMapper"
    replace: "import tools.jackson.databind.json.JsonMapper"
note: |
  [MANUAL-REVIEW] ObjectMapper still exists in Jackson 3 for backward compatibility, 
  but JsonMapper is the preferred type. Complex configurations need manual migration.
```

### Rule 5.4 — Spring Boot Annotation Renames

```yaml
scope: "**/*.java"
priority: CRITICAL
rewrites:
  - find: "@JsonComponent"
    replace: "@JacksonComponent"
    import_old: "org.springframework.boot.jackson.JsonComponent"
    import_new: "org.springframework.boot.jackson.JacksonComponent"
  - find: "@JsonMixin"
    replace: "@JacksonMixin"
    import_old: "org.springframework.boot.jackson.JsonMixin"
    import_new: "org.springframework.boot.jackson.JacksonMixin"
```

### Rule 5.5 — Jackson Serializer/Deserializer Class Renames

```yaml
scope: "**/*.java"
priority: HIGH
condition: "Application has custom Jackson serializers or deserializers"
rewrites:
  - find: "extends JsonObjectSerializer"
    replace: "extends ObjectValueSerializer"
  - find: "extends JsonObjectDeserializer"
    replace: "extends ObjectValueDeserializer"
  - find: "import org.springframework.boot.jackson.JsonObjectSerializer"
    replace: "import org.springframework.boot.jackson.ObjectValueSerializer"
  - find: "import org.springframework.boot.jackson.JsonObjectDeserializer"
    replace: "import org.springframework.boot.jackson.ObjectValueDeserializer"
note: "[MANUAL-REVIEW] Review serialize/deserialize method signatures for breaking changes"
```

### Rule 5.6 — Jackson 2 ObjectMapperBuilder → Jackson 3 JsonMapper.builder()

```yaml
scope: "**/*.java"
priority: HIGH
condition: "Application uses Jackson2ObjectMapperBuilder"
description: "Migrate ObjectMapper configuration from Jackson 2 builder to Jackson 3 builder"
example_before: |
  @Bean
  public ObjectMapper objectMapper() {
      return Jackson2ObjectMapperBuilder.json()
          .serializationInclusion(JsonInclude.Include.NON_EMPTY)
          .featuresToDisable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS,
                             SerializationFeature.FAIL_ON_EMPTY_BEANS)
          .featuresToEnable(DeserializationFeature.ACCEPT_SINGLE_VALUE_AS_ARRAY)
          .modulesToInstall(JavaTimeModule.class)
          .build();
  }
example_after: |
  @Bean
  JsonMapper jacksonJsonMapper() {
      return JsonMapper.builder()
          .changeDefaultPropertyInclusion(v ->
              v.withValueInclusion(JsonInclude.Include.NON_EMPTY))
          .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)
          .disable(SerializationFeature.FAIL_ON_EMPTY_BEANS)
          .enable(DeserializationFeature.ACCEPT_SINGLE_VALUE_AS_ARRAY)
          .addModule(new JavaTimeModule())
          .build();
  }
note: "[MANUAL-REVIEW] Jackson 3 builder API differs — review each method call"
```

### Rule 5.7 — Jackson 2 Fallback Mode (Temporary Bridge)

```yaml
scope: "**/application.properties, **/application.yml"
priority: MEDIUM
condition: "Need to temporarily keep Jackson 2 for specific libraries"
description: |
  If some libraries still require Jackson 2, you can run both side by side.
  Add a manually configured Jackson 2 ObjectMapper alongside Boot's Jackson 3 auto-config.
action_properties: |
  # For Web MVC:
  spring.http.converters.preferred-json-mapper=jackson2
  # For WebFlux:
  spring.http.codecs.preferred-json-mapper=jackson2
action_yaml: |
  spring:
    http:
      converters:
        preferred-json-mapper: jackson2
note: "TEMPORARY — remove once all dependencies support Jackson 3"
```

### Rule 5.8 — Jackson Module Auto-Discovery

```yaml
scope: "**/application.properties, **/application.yml, **/*.java"
priority: MEDIUM
description: |
  Spring Boot 4 auto-detects ALL Jackson modules on the classpath (not just well-known ones).
  If this causes issues (duplicate modules, conflicting behavior), disable it.
action: |
  To disable: spring.jackson.find-and-add-modules=false
  Then register modules explicitly in your JsonMapper bean.
```

---

## 6. Spring Security 6 → 7

### Rule 6.1 — WebSecurityConfigurerAdapter (Must Be Gone)

```yaml
scope: "**/*.java"
priority: CRITICAL
find_regex: "extends\s+WebSecurityConfigurerAdapter"
action: |
  This class was removed in Spring Security 6 (should already be gone in Boot 3).
  If still present, refactor to SecurityFilterChain @Bean pattern:
  
  @Configuration
  @EnableWebSecurity
  public class SecurityConfig {
      @Bean
      public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
          http.authorizeHttpRequests(auth -> auth
              .requestMatchers("/public/**").permitAll()
              .anyRequest().authenticated()
          );
          return http.build();
      }
  }
validate: "No class in codebase extends WebSecurityConfigurerAdapter"
```

### Rule 6.2 — Deprecated authorizeRequests() → authorizeHttpRequests()

```yaml
scope: "**/*.java"
priority: HIGH
find: ".authorizeRequests()"
replace: ".authorizeHttpRequests()"
additional:
  - find: ".antMatchers("
    replace: ".requestMatchers("
  - find: ".mvcMatchers("
    replace: ".requestMatchers("
note: "antMatchers and mvcMatchers were deprecated in Security 6, removed in 7"
```

### Rule 6.3 — Spring Security Test Dependency

```yaml
scope: "**/pom.xml, **/build.gradle*"
priority: CRITICAL
condition: "Tests use @WithMockUser, @WithUserDetails, or other Spring Security test annotations"
action: |
  ADD dependency:
    Maven:  <dependency>
              <groupId>org.springframework.boot</groupId>
              <artifactId>spring-boot-starter-security-test</artifactId>
              <scope>test</scope>
            </dependency>
    Gradle: testImplementation 'org.springframework.boot:spring-boot-starter-security-test'
```

### Rule 6.4 — CSRF and Security Header Updates

```yaml
scope: "**/*.java"
priority: MEDIUM
description: "Spring Security 7 has updated CSRF and TLS security defaults"
action: |
  Review your CSRF configuration. If you have custom CSRF token handling,
  verify it works with the new defaults.
  Review any custom security headers configuration.
note: "[MANUAL-REVIEW] Test all authenticated endpoints"
```

---

## 7. Hibernate 6 → 7 / JPA

### Rule 7.1 — Jakarta Persistence 3.2

```yaml
scope: "**/*.java"
priority: HIGH
description: "Hibernate 7 implements Jakarta Persistence 3.2"
validate: |
  All JPA imports should already use jakarta.persistence.* (migrated in Boot 3).
  Verify: grep -r "import javax.persistence" src/ should return nothing.
```

### Rule 7.2 — Entity Lifecycle: merge() Behavior Change

```yaml
scope: "**/*.java"
priority: HIGH
condition: "Application uses EntityManager.merge() for detached entities"
description: |
  Hibernate 7 no longer allows a detached entity to be reassociated with a session 
  the same way. merge() returns a NEW managed instance — the original remains detached.
action: |
  Review all uses of:
    - entityManager.merge(entity)
    - session.merge(entity)
  Ensure code uses the RETURNED entity, not the original:
    // WRONG:
    entityManager.merge(entity);
    entity.setFoo("bar"); // entity is still detached!
    
    // CORRECT:
    entity = entityManager.merge(entity);
    entity.setFoo("bar"); // entity is now managed
note: "[MANUAL-REVIEW] Critical — can cause silent data loss"
```

### Rule 7.3 — Fetch Behavior Changes

```yaml
scope: "**/*.java"
priority: HIGH
description: |
  Hibernate 7 may change default fetch strategies and SQL generation.
  Lazy/eager loading behavior may differ from Hibernate 6.
action: |
  1. Enable Hibernate SQL logging temporarily: spring.jpa.show-sql=true
  2. Run integration tests and compare generated SQL
  3. Review any @Fetch annotations and FetchType overrides
  4. Test N+1 query scenarios
note: "[MANUAL-REVIEW] Run full integration test suite with SQL logging"
```

### Rule 7.4 — Hibernate Configuration Properties

```yaml
scope: "**/application.properties, **/application.yml"
priority: MEDIUM
description: "Several Hibernate configuration keys have been renamed/deprecated"
action: |
  Review all properties under:
    spring.jpa.properties.hibernate.*
    spring.jpa.hibernate.*
  Cross-reference with Hibernate 7 migration guide for renamed keys.
note: "[MANUAL-REVIEW] Check Hibernate 7 release notes for specific key changes"
```

### Rule 7.5 — open-in-view Warning

```yaml
scope: "**/application.properties, **/application.yml"
priority: LOW
description: "spring.jpa.open-in-view is still supported but discouraged"
recommendation: |
  spring.jpa.open-in-view=false
  This prevents lazy loading in the view layer and improves performance predictability.
```

---

## 8. Testing

### Rule 8.1 — @MockBean → @MockitoBean

```yaml
scope: "**/*.java"
priority: CRITICAL
description: "@MockBean and @SpyBean (deprecated 3.4) are REMOVED in Boot 4"
rewrites:
  - find: "@MockBean"
    replace: "@MockitoBean"
    import_old: "org.springframework.boot.test.mock.mockito.MockBean"
    import_new: "org.springframework.test.context.bean.override.mockito.MockitoBean"
  - find: "@SpyBean"
    replace: "@MockitoSpyBean"
    import_old: "org.springframework.boot.test.mock.mockito.SpyBean"
    import_new: "org.springframework.test.context.bean.override.mockito.MockitoSpyBean"
validate: "grep -r '@MockBean\|@SpyBean' src/ returns nothing (excluding this playbook)"
```

### Rule 8.2 — MockitoTestExecutionListener Removal

```yaml
scope: "**/*.java"
priority: HIGH
description: "MockitoTestExecutionListener is removed. Use MockitoExtension."
find: "MockitoTestExecutionListener"
action: |
  If tests rely on MockitoTestExecutionListener (possibly indirectly):
  Add @ExtendWith(MockitoExtension.class) to test classes using @Mock or @Captor.
```

```yaml
scope: "**/*.java"
find_regex: "@Mock\b|@Captor\b"
condition: "Class does NOT have @ExtendWith(MockitoExtension.class)"
action: "Add @ExtendWith(MockitoExtension.class) to the class"
import_add: "import org.junit.jupiter.api.extension.ExtendWith; import org.mockito.junit.jupiter.MockitoExtension;"
```

### Rule 8.3 — JUnit 4 Removal

```yaml
scope: "**/*.java"
priority: CRITICAL
description: "JUnit 4 support is completely removed in Spring Boot 4"
find_patterns:
  - "import org.junit.Test"
  - "import org.junit.Before"
  - "import org.junit.After"
  - "import org.junit.Ignore"
  - "import org.junit.runner.RunWith"
  - "import org.junit.Assert."
  - "@RunWith("
action: |
  Migrate all JUnit 4 tests to JUnit Jupiter 5/6:
    org.junit.Test          → org.junit.jupiter.api.Test
    org.junit.Before        → org.junit.jupiter.api.BeforeEach
    org.junit.After         → org.junit.jupiter.api.AfterEach
    org.junit.BeforeClass   → org.junit.jupiter.api.BeforeAll
    org.junit.AfterClass    → org.junit.jupiter.api.AfterAll
    org.junit.Ignore        → org.junit.jupiter.api.Disabled
    org.junit.Assert.*      → org.junit.jupiter.api.Assertions.*
    @RunWith(SpringRunner.class) → @ExtendWith(SpringExtension.class) (or just @SpringBootTest)
    @RunWith(MockitoJUnitRunner.class) → @ExtendWith(MockitoExtension.class)
validate: "grep -r 'import org.junit.' src/test/ returns only org.junit.jupiter imports"
```

### Rule 8.4 — JUnit 4 Maven/Gradle Dependencies

```yaml
scope: "**/pom.xml, **/build.gradle*"
priority: HIGH
find_patterns:
  - "junit:junit"
  - "junit-vintage-engine"
action: "Remove JUnit 4 and vintage engine dependencies. JUnit Jupiter is included via spring-boot-starter-test."
```

### Rule 8.5 — RestTestClient (New)

```yaml
scope: "**/*.java"
priority: LOW
condition: "Tests use WebTestClient for non-reactive (servlet) applications"
description: |
  Spring Boot 4 adds RestTestClient — a non-reactive equivalent of WebTestClient.
  Consider adopting for cleaner test code in MVC applications.
note: "Optional — existing WebTestClient usage still works"
```

### Rule 8.6 — Testcontainers 2.0

```yaml
scope: "**/*.java, **/pom.xml, **/build.gradle*"
priority: MEDIUM
condition: "Application uses Testcontainers"
description: "Spring Boot 4 upgrades to Testcontainers 2.0 which has API changes"
action: |
  Review Testcontainers 2.0 migration guide for breaking changes.
  Common changes:
    - Package relocations
    - API method signature changes
    - @ServiceConnection support for MongoDB now supports MongoDBAtlasLocalContainer
```

---

## 9. Configuration Properties

### Rule 9.1 — Jackson Property Renames

```yaml
scope: "**/application.properties, **/application.yml, **/application-*.properties, **/application-*.yml"
priority: CRITICAL
rewrites:
  - find: "spring.jackson.read."
    replace: "spring.jackson.json.read."
  - find: "spring.jackson.write."
    replace: "spring.jackson.json.write."
  - find: "spring.jackson.datetime."
    replace: "spring.jackson.json.datetime."
validate: "grep -r 'spring.jackson.read\.\|spring.jackson.write\.\|spring.jackson.datetime\.' src/main/resources/ returns nothing"
```

### Rule 9.2 — ConfigurationProperties: No Public Field Binding

```yaml
scope: "**/*.java"
priority: CRITICAL
description: "Spring Boot 4 removes binding to public fields in @ConfigurationProperties classes"
find_regex: "@ConfigurationProperties"
action: |
  For every class annotated with @ConfigurationProperties:
  1. Find all public fields
  2. Make them private
  3. Add getter and setter methods
  
  BEFORE (broken):
    @ConfigurationProperties("app")
    public class AppProps {
        public String name;
        public int timeout;
    }
  
  AFTER (correct):
    @ConfigurationProperties("app")
    public class AppProps {
        private String name;
        private int timeout;
        public String getName() { return name; }
        public void setName(String name) { this.name = name; }
        public int getTimeout() { return timeout; }
        public void setTimeout(int timeout) { this.timeout = timeout; }
    }
  
  ALTERNATIVE — use Java records (immutable binding):
    @ConfigurationProperties("app")
    public record AppProps(String name, int timeout) {}
validate: "No @ConfigurationProperties class has public non-static non-final fields"
```

### Rule 9.3 — MongoDB Property Renames

```yaml
scope: "**/application.properties, **/application.yml"
priority: HIGH
condition: "Application uses MongoDB"
description: "Many MongoDB properties have been renamed in Spring Boot 4"
action: |
  Review all properties starting with spring.data.mongodb.*
  Cross-reference with the Spring Boot 4 migration guide for specific renames.
  Also note: MongoDB health indicators moved from spring-boot-data-mongodb to spring-boot-mongodb.
  New property: spring.data.mongodb.representation.big-decimal controls BigDecimal storage.
note: "[MANUAL-REVIEW] Check release notes for complete MongoDB property rename list"
```

### Rule 9.4 — Tracing Property Updates

```yaml
scope: "**/application.properties, **/application.yml"
priority: MEDIUM
condition: "Application uses distributed tracing (Micrometer Tracing, Zipkin, etc.)"
description: "Several tracing-related properties have been updated"
action: "Review all management.tracing.* and management.zipkin.* properties against Boot 4 docs"
note: "[MANUAL-REVIEW]"
```

### Rule 9.5 — PropertyMapper API Change

```yaml
scope: "**/*.java"
priority: MEDIUM
condition: "Application uses Spring Boot's PropertyMapper utility"
description: |
  PropertyMapper no longer calls adapter/predicate methods by default for null values.
  alwaysApplyingNotNull() is removed. Use always() for null-inclusive mapping.
find: ".alwaysApplyingNotNull()"
replace: ".always()"
note: "[MANUAL-REVIEW] Review PropertyMapper usage for null-handling correctness"
```

---

## 10. Spring Batch 5 → 6

### Rule 10.1 — In-Memory Default

```yaml
scope: "**/application.properties, **/application.yml, **/*.java"
priority: HIGH
condition: "Application uses Spring Batch"
description: |
  Spring Batch can now operate without a database (in-memory mode).
  The basic spring-boot-starter-batch uses this simplified mode.
  On upgrade, Spring Batch will NO LONGER store metadata in your database.
action: |
  If you need database-backed batch metadata (job restart, history, etc.):
    Switch to: spring-boot-starter-batch-jdbc
  If in-memory is acceptable:
    Use: spring-boot-starter-batch (no change needed)
note: "[MANUAL-REVIEW] CRITICAL if you rely on batch job restart after failures"
```

### Rule 10.2 — RabbitRetryTemplateCustomizer

```yaml
scope: "**/*.java"
priority: MEDIUM
condition: "Application uses RabbitRetryTemplateCustomizer"
description: "RabbitRetryTemplateCustomizer has been removed"
action: |
  Migrate to one of:
    - RabbitRetryTemplateCustomizer (target-based, if renamed in your version)
    - Direct RetryTemplate configuration
  Check Spring AMQP 4.0 migration guide for exact replacement.
```

---

## 11. Observability & Actuator

### Rule 11.1 — Micrometer 2 / Actuator 4

```yaml
scope: "**/application.properties, **/application.yml, **/*.java"
priority: MEDIUM
description: |
  Spring Boot 4 ships with Micrometer 2 and Actuator 4.
  Unified metrics, logs, and traces with minimal setup.
  @MeterTag is now supported on @Counted and @Timed methods with SpEL.
action: |
  1. Review custom MeterRegistry configurations
  2. Review actuator endpoint exposure settings
  3. HttpMessageConverters is deprecated — update if you customized it for actuator
  4. Optional actuator endpoint parameters must use JSpecify @Nullable (not @OptionalParameter)
```

### Rule 11.2 — @OptionalParameter Removed

```yaml
scope: "**/*.java"
priority: HIGH
condition: "Application has custom actuator endpoints"
find: "@OptionalParameter"
replace: "@Nullable"
import_add: "import org.jspecify.annotations.Nullable;"
import_remove: "import org.springframework.boot.actuate.endpoint.annotation.OptionalParameter;"
```

### Rule 11.3 — HttpMessageConverters Deprecation

```yaml
scope: "**/*.java"
priority: MEDIUM
find: "HttpMessageConverters"
description: |
  HttpMessageConverters is deprecated in favor of Spring Framework 7's improved support.
  Review any custom HttpMessageConverter configurations.
note: "[MANUAL-REVIEW] Not yet removed, but plan migration"
```

---

## 12. Resilience (New)

### Rule 12.1 — Native @Retryable (Spring Framework 7)

```yaml
scope: "**/*.java"
priority: LOW
condition: "Application uses Resilience4j or Spring Retry for retry logic"
description: |
  Spring Framework 7 includes built-in resilience features:
    @Retryable — declarative retry with exponential backoff and jitter
    @ConcurrencyLimit — declarative concurrency control
    RetryTemplate — programmatic retry
  These reduce or eliminate the need for Resilience4j or Spring Retry.
example: |
  @Service
  public class ExternalApiService {
      @Retryable(
          includes = GatewayTimeoutException.class,
          maxAttempts = 3,
          backoff = @Backoff(delay = 500, multiplier = 2)
      )
      @ConcurrencyLimit(5)
      public ApiResponse callExternal(String key) {
          return client.get(key);
      }
  }
note: |
  [MANUAL-REVIEW] Optional adoption. Evaluate whether to replace Resilience4j.
  For reactive methods, retry logic automatically decorates the Reactor pipeline.
```

---

## 13. API Versioning (New)

### Rule 13.1 — Native API Versioning

```yaml
scope: "**/*.java"
priority: LOW
description: |
  Spring Boot 4 / Spring Framework 7 adds first-class API versioning.
  Supports: path, header, query parameter, and media type strategies.
  No more custom filters or URL-based version hacks needed.
example: |
  @RestController
  @RequestMapping("/api/users")
  @ApiVersion("1")
  public class UserControllerV1 {
      @GetMapping
      public List<UserDtoV1> getUsers() { ... }
  }
  
  @RestController
  @RequestMapping("/api/users")
  @ApiVersion("2")
  public class UserControllerV2 {
      @GetMapping
      public List<UserDtoV2> getUsers() { ... }
  }
  
  // Or version at the method level:
  @GetMapping(url = "/accounts/{id}", version = "1.1")
  public Account getAccount(@PathVariable String id) { ... }
note: "Optional — adopt when ready. Built-in deprecation handling per RFC 9745."
```

---

## 14. HTTP Service Clients (New)

### Rule 14.1 — Declarative HTTP Clients

```yaml
scope: "**/*.java"
priority: LOW
condition: "Application uses OpenFeign or manual RestTemplate/WebClient wrappers"
description: |
  Spring Boot 4 supports declarative HTTP service clients via @HttpServiceClient.
  Consider adopting to replace OpenFeign or manual HTTP client code.
example: |
  @HttpServiceClient(
      name = "user-service",
      url = "${clients.user-service.base-url}"
  )
  public interface UserServiceClient {
      @GetMapping("/users/{id}")
      UserDto getUser(@PathVariable Long id);
      
      @PostMapping("/users")
      UserDto createUser(@RequestBody CreateUserRequest request);
  }
note: "Optional — evaluate as replacement for OpenFeign or manual RestClient wrappers"
```

---

## 15. Null Safety — JSpecify

### Rule 15.1 — JSR-305 to JSpecify Migration

```yaml
scope: "**/*.java"
priority: MEDIUM
description: |
  Spring Framework 7 migrates from JSR-305 to JSpecify annotations for null safety.
  Your code may reference JSR-305 annotations that should be updated.
rewrites:
  - find: "import javax.annotation.Nullable"
    replace: "import org.jspecify.annotations.Nullable"
  - find: "import javax.annotation.Nonnull"
    replace: "import org.jspecify.annotations.NonNull"
  - find: "import org.springframework.lang.Nullable"
    replace: "import org.jspecify.annotations.Nullable"
  - find: "import org.springframework.lang.NonNull"
    replace: "import org.jspecify.annotations.NonNull"
note: |
  [MANUAL-REVIEW] JSpecify annotations have slightly different semantics.
  Kotlin users benefit automatically — API nullability is now accurately inferred.
  IntelliJ IDEA 2025.3+ provides full support.
```

### Rule 15.2 — Add JSpecify Dependency (if not transitively included)

```yaml
scope: "**/pom.xml, **/build.gradle*"
priority: MEDIUM
condition: "Using @Nullable / @NonNull annotations directly"
action: |
  Maven:
    <dependency>
      <groupId>org.jspecify</groupId>
      <artifactId>jspecify</artifactId>
    </dependency>
  Gradle:
    implementation 'org.jspecify:jspecify'
  Note: Version managed by Spring Boot 4 BOM.
```

---

## 16. Removed Features

### Rule 16.1 — Undertow Server Removal

```yaml
scope: "**/pom.xml, **/build.gradle*, **/*.java, **/application.properties, **/application.yml"
priority: CRITICAL
condition: "Application uses Undertow as embedded server"
actions:
  - find: "spring-boot-starter-undertow"
    action: "REMOVE this dependency. Switch to Tomcat (default) or Jetty."
  - find: "server.undertow."
    action: "Remove all Undertow-specific properties"
  - find: "import io.undertow"
    action: "Remove Undertow-specific code"
replacement: |
  For Jetty: Add spring-boot-starter-jetty and exclude spring-boot-starter-tomcat
  For Tomcat: No action needed (it's the default)
```

### Rule 16.2 — Executable Launch Scripts

```yaml
scope: "**/pom.xml, **/build.gradle*"
priority: HIGH
find_patterns:
  - "<executable>true</executable>"
  - "launchScript()"
  - "executable = true"
action: "Remove executable launch script configuration. Use java -jar to run."
```

### Rule 16.3 — Spock Test Framework

```yaml
scope: "**/*.groovy, **/pom.xml, **/build.gradle*"
priority: HIGH
condition: "Application uses Spock for testing"
description: "Spring Boot's Spock integration is removed (incompatible with Groovy 5)"
action: "Migrate Spock tests to JUnit Jupiter"
```

### Rule 16.4 — Spring Session Hazelcast/MongoDB

```yaml
scope: "**/pom.xml, **/build.gradle*"
priority: MEDIUM
condition: "Application uses Spring Session with Hazelcast or MongoDB"
description: |
  Spring Session Hazelcast is now maintained by Hazelcast team.
  Spring Session MongoDB is now maintained by MongoDB team.
action: "Update to the community-maintained dependencies"
```

### Rule 16.5 — Spring JCL Logging Bridge

```yaml
scope: "**/pom.xml, **/build.gradle*"
priority: MEDIUM
description: "Spring JCL logging bridge is removed in favor of Apache Commons Logging"
action: "Remove explicit spring-jcl dependencies if present. Commons Logging is used automatically."
```

### Rule 16.6 — Auto-Configuration Class Visibility

```yaml
scope: "**/*.java"
priority: MEDIUM
description: |
  Auto-configuration classes are no longer public API.
  Public members (aside from constants) have been removed from auto-configuration classes.
action: |
  If your code directly references or extends Spring Boot auto-configuration classes,
  review and refactor to use the intended public API instead.
note: "[MANUAL-REVIEW]"
```

---

## 17. Docker & Deployment

### Rule 17.1 — Base Image Update

```yaml
scope: "**/Dockerfile, **/docker-compose*.yml, **/*.yaml"
priority: CRITICAL
rewrites:
  - find_regex: "eclipse-temurin:21[^ ]*"
    replace: "eclipse-temurin:25-jre-noble"
  - find_regex: "amazoncorretto:21[^ ]*"
    replace: "amazoncorretto:25"
  - find_regex: "openjdk:21[^ ]*"
    replace: "eclipse-temurin:25-jre-noble"
    note: "openjdk Docker images are deprecated; switch to eclipse-temurin or amazoncorretto"
```

### Rule 17.2 — GraalVM Native Image

```yaml
scope: "**/pom.xml, **/build.gradle*"
priority: HIGH
condition: "Application uses GraalVM native image compilation"
description: "GraalVM 25 or later is required. Experimental Graal JIT compiler has been removed from JDK 25."
action: |
  1. Update GraalVM to version 25+
  2. Review reachability metadata format (new exact format in GraalVM 25)
  3. Test native image build early — reflection-heavy code may need migration
  4. Review AOT compilation settings
```

### Rule 17.3 — Servlet Container Compatibility

```yaml
scope: "**/pom.xml, **/build.gradle*, **/server.xml, **/web.xml"
priority: HIGH
condition: "Application deployed to external servlet container (WAR deployment)"
description: |
  Spring Boot 4 requires Servlet 6.1 baseline:
    - Tomcat 11.0+
    - Jetty 12.1+
    - Undertow is NOT supported
  Do NOT deploy to non-Servlet 6.1 containers.
action: "Verify external container version meets Servlet 6.1 requirement"
```

### Rule 17.4 — CI/CD Pipeline Updates

```yaml
scope: "**/.github/workflows/*.yml, **/Jenkinsfile, **/.gitlab-ci.yml, **/azure-pipelines.yml"
priority: HIGH
actions:
  - description: "Update Java version in CI"
    find_regex: "java-version:\s*['\"]?21['\"]?"
    replace: "java-version: '25'"
  - description: "Update setup-java action"
    find_regex: "distribution:\s*['\"]temurin['\"]"
    note: "Keep temurin, just update version"
  - description: "Update Gradle wrapper version if needed"
    note: "Ensure CI uses Gradle 8.14+ or 9.x"
```

---

## 18. Validation & Smoke Tests

### Rule 18.1 — Compilation Check

```yaml
priority: CRITICAL
commands:
  maven: "mvn clean compile -DskipTests"
  gradle: "./gradlew clean compileJava"
expected: "BUILD SUCCESS with zero errors"
on_failure: "Fix compilation errors before proceeding. Most common: missing imports after Jackson/starter changes."
```

### Rule 18.2 — Test Suite

```yaml
priority: CRITICAL
commands:
  maven: "mvn test"
  gradle: "./gradlew test"
expected: "All tests pass"
common_failures:
  - "NoClassDefFoundError for MockBean → Apply Rule 8.1"
  - "Jackson serialization errors → Apply Rules 5.1–5.8"
  - "Security test failures → Apply Rule 6.3"
  - "Hibernate query changes → Apply Rule 7.3"
```

### Rule 18.3 — Startup Smoke Test

```yaml
priority: CRITICAL
command: "java -jar target/app.jar --spring.main.banner-mode=off"
expected: "Application starts without errors"
checks:
  - "No ClassNotFoundException or NoSuchMethodError in startup log"
  - "Actuator health endpoint returns UP: curl http://localhost:8080/actuator/health"
  - "Application context loads all beans without circular dependency errors"
```

### Rule 18.4 — JSON Serialization Smoke Test

```yaml
priority: HIGH
description: "Jackson 3 migration is the highest-risk area. Verify all JSON endpoints."
checks:
  - "All REST API endpoints return correct JSON structure"
  - "Date/time fields serialize correctly (Jackson 3 may change Locale serialization)"
  - "Custom serializers/deserializers produce correct output"
  - "API contract tests (if any) pass"
```

### Rule 18.5 — Performance Baseline Comparison

```yaml
priority: MEDIUM
checks:
  - "Startup time: compare against pre-migration baseline (expect improvement with Java 25 AOT)"
  - "Memory usage: compare RSS/heap (expect improvement with compact object headers)"
  - "Throughput: run load test and compare against baseline"
  - "GC pause times: compare JFR recordings"
```

### Rule 18.6 — Dependency Audit

```yaml
priority: MEDIUM
commands:
  maven: "mvn dependency:tree > deps.txt"
  gradle: "./gradlew dependencies > deps.txt"
checks:
  - "No javax.* dependencies remain (should all be jakarta.*)"
  - "No Jackson 2 on classpath (unless intentionally kept via Rule 5.7)"
  - "No JUnit 4 on classpath"
  - "No conflicting Spring Framework versions (should all be 7.x)"
  - "No Undertow dependencies"
```

---

## Appendix A: Full Import Rewrite Map

```text
# ══════════════════════════════════════════════════════════════════
# JACKSON IMPORTS (Section 5)
# ══════════════════════════════════════════════════════════════════
com.fasterxml.jackson.databind.*              → tools.jackson.databind.*
com.fasterxml.jackson.core.*                  → tools.jackson.core.*
com.fasterxml.jackson.datatype.*              → tools.jackson.datatype.*
com.fasterxml.jackson.dataformat.*            → tools.jackson.dataformat.*
com.fasterxml.jackson.module.*                → tools.jackson.module.*
com.fasterxml.jackson.annotation.*            → NO CHANGE (stays same)

# ══════════════════════════════════════════════════════════════════
# SPRING BOOT JACKSON ANNOTATIONS (Section 5)
# ══════════════════════════════════════════════════════════════════
o.s.boot.jackson.JsonComponent                → o.s.boot.jackson.JacksonComponent
o.s.boot.jackson.JsonMixin                    → o.s.boot.jackson.JacksonMixin
o.s.boot.jackson.JsonObjectSerializer         → o.s.boot.jackson.ObjectValueSerializer
o.s.boot.jackson.JsonObjectDeserializer       → o.s.boot.jackson.ObjectValueDeserializer

# ══════════════════════════════════════════════════════════════════
# TESTING IMPORTS (Section 8)
# ══════════════════════════════════════════════════════════════════
o.s.boot.test.mock.mockito.MockBean           → o.s.test.context.bean.override.mockito.MockitoBean
o.s.boot.test.mock.mockito.SpyBean            → o.s.test.context.bean.override.mockito.MockitoSpyBean

# JUNIT 4 → JUPITER
org.junit.Test                                → org.junit.jupiter.api.Test
org.junit.Before                              → org.junit.jupiter.api.BeforeEach
org.junit.After                               → org.junit.jupiter.api.AfterEach
org.junit.BeforeClass                         → org.junit.jupiter.api.BeforeAll
org.junit.AfterClass                          → org.junit.jupiter.api.AfterAll
org.junit.Ignore                              → org.junit.jupiter.api.Disabled
org.junit.Assert                              → org.junit.jupiter.api.Assertions
org.junit.runner.RunWith                      → org.junit.jupiter.api.extension.ExtendWith
org.junit.runners.Parameterized               → org.junit.jupiter.params.ParameterizedTest

# ══════════════════════════════════════════════════════════════════
# NULL SAFETY (Section 15)
# ══════════════════════════════════════════════════════════════════
javax.annotation.Nullable                     → org.jspecify.annotations.Nullable
javax.annotation.Nonnull                      → org.jspecify.annotations.NonNull
org.springframework.lang.Nullable             → org.jspecify.annotations.Nullable
org.springframework.lang.NonNull              → org.jspecify.annotations.NonNull

# ══════════════════════════════════════════════════════════════════
# ACTUATOR (Section 11)
# ══════════════════════════════════════════════════════════════════
o.s.boot.actuate.endpoint.annotation.OptionalParameter → org.jspecify.annotations.Nullable
```

---

## Appendix B: Property Rename Map

```properties
# ══════════════════════════════════════════════════════════════════
# application.properties / application.yml RENAMES
# ══════════════════════════════════════════════════════════════════

# JACKSON (Critical)
spring.jackson.read.<feature>                 = spring.jackson.json.read.<feature>
spring.jackson.write.<feature>                = spring.jackson.json.write.<feature>
spring.jackson.datetime.<feature>             = spring.jackson.json.datetime.<feature>

# JACKSON — new property
# spring.jackson.find-and-add-modules=true    (default; set false to disable auto-discovery)

# JACKSON — fallback to Jackson 2
# spring.http.converters.preferred-json-mapper=jackson2   (Web MVC)
# spring.http.codecs.preferred-json-mapper=jackson2       (WebFlux)

# MONGODB — check release notes for full rename list
# spring.data.mongodb.*                       → multiple renames, see Boot 4 migration guide
# NEW: spring.data.mongodb.representation.big-decimal

# BATCH — behavioral change (no property rename)
# spring-boot-starter-batch now uses in-memory mode by default
# Use spring-boot-starter-batch-jdbc for database-backed metadata

# TRACING — review all management.tracing.* and management.zipkin.* properties

# ══════════════════════════════════════════════════════════════════
# Add your organization-specific property renames below:
# ══════════════════════════════════════════════════════════════════
# [OLD_PROPERTY]                              = [NEW_PROPERTY]
```

---

## Appendix C: OpenRewrite Automation

### Maven Configuration

```xml
<plugin>
    <groupId>org.openrewrite.maven</groupId>
    <artifactId>rewrite-maven-plugin</artifactId>
    <version>6.28.1</version>
    <configuration>
        <exportDatatables>true</exportDatatables>
        <activeRecipes>
            <recipe>org.openrewrite.java.spring.boot4.UpgradeSpringBoot_4_0</recipe>
        </activeRecipes>
    </configuration>
    <dependencies>
        <dependency>
            <groupId>org.openrewrite.recipe</groupId>
            <artifactId>rewrite-spring</artifactId>
            <version>6.23.1</version>
        </dependency>
    </dependencies>
</plugin>
```

Run: `mvn rewrite:run`

### Gradle Configuration

```groovy
plugins {
    id("org.openrewrite.rewrite") version("latest.release")
}

rewrite {
    activeRecipe("org.openrewrite.java.spring.boot4.UpgradeSpringBoot_4_0")
    setExportDatatables(true)
}

repositories {
    mavenCentral()
}

dependencies {
    rewrite("org.openrewrite.recipe:rewrite-spring:6.23.1")
}
```

Run: `gradle rewriteRun`

### What the Composite Recipe Includes

```text
org.openrewrite.java.spring.boot4.UpgradeSpringBoot_4_0
  ├── org.openrewrite.java.spring.boot3.UpgradeSpringBoot_3_5
  ├── org.openrewrite.java.spring.framework.UpgradeSpringFramework_7_0
  ├── org.openrewrite.java.spring.security7.UpgradeSpringSecurity_7_0
  ├── org.openrewrite.java.spring.batch.SpringBatch5To6Migration
  ├── org.openrewrite.java.spring.boot4.SpringBootProperties_4_0
  ├── org.openrewrite.java.spring.boot4.ReplaceMockBeanAndSpyBean
  ├── org.openrewrite.hibernate.MigrateToHibernate71
  ├── org.openrewrite.java.testing.testcontainers.Testcontainers2Migration
  ├── org.openrewrite.java.springdoc.UpgradeSpringDoc_3_0
  ├── org.openrewrite.java.spring.boot4.MigrateToModularStarters
  └── org.openrewrite.java.jackson.UpgradeJackson_2_3
```

---

## Appendix D: Quick Validation Script

```bash
#!/bin/bash
# migration-validate.sh — Run after migration to check for common issues

set -e
echo "=== Migration Validation ==="

echo "[1/8] Checking for remaining javax.* imports..."
JAVAX_COUNT=$(grep -r "import javax\." src/ --include="*.java" | grep -v "javax.annotation" | wc -l || true)
if [ "$JAVAX_COUNT" -gt 0 ]; then
    echo "  ❌ Found $JAVAX_COUNT javax.* imports (should be jakarta.*)"
    grep -r "import javax\." src/ --include="*.java" | grep -v "javax.annotation" | head -20
else
    echo "  ✅ No javax.* imports found"
fi

echo "[2/8] Checking for old Jackson 2 imports..."
JACKSON2_COUNT=$(grep -r "import com\.fasterxml\.jackson\." src/ --include="*.java" | grep -v "annotation" | wc -l || true)
if [ "$JACKSON2_COUNT" -gt 0 ]; then
    echo "  ❌ Found $JACKSON2_COUNT Jackson 2 imports (should be tools.jackson.*)"
    grep -r "import com\.fasterxml\.jackson\." src/ --include="*.java" | grep -v "annotation" | head -20
else
    echo "  ✅ No Jackson 2 imports found (excluding annotations)"
fi

echo "[3/8] Checking for removed @MockBean/@SpyBean..."
MOCKBEAN_COUNT=$(grep -r "@MockBean\|@SpyBean" src/ --include="*.java" | grep -v "MockitoBean\|MockitoSpyBean" | wc -l || true)
if [ "$MOCKBEAN_COUNT" -gt 0 ]; then
    echo "  ❌ Found $MOCKBEAN_COUNT @MockBean/@SpyBean usages"
    grep -r "@MockBean\|@SpyBean" src/ --include="*.java" | grep -v "MockitoBean\|MockitoSpyBean" | head -20
else
    echo "  ✅ No @MockBean/@SpyBean found"
fi

echo "[4/8] Checking for JUnit 4 imports..."
JUNIT4_COUNT=$(grep -r "import org\.junit\." src/ --include="*.java" | grep -v "jupiter" | wc -l || true)
if [ "$JUNIT4_COUNT" -gt 0 ]; then
    echo "  ❌ Found $JUNIT4_COUNT JUnit 4 imports"
    grep -r "import org\.junit\." src/ --include="*.java" | grep -v "jupiter" | head -20
else
    echo "  ✅ No JUnit 4 imports found"
fi

echo "[5/8] Checking for old Jackson property names..."
OLD_JACKSON_PROPS=$(grep -r "spring\.jackson\.read\.\|spring\.jackson\.write\.\|spring\.jackson\.datetime\." src/main/resources/ 2>/dev/null | grep -v "json\." | wc -l || true)
if [ "$OLD_JACKSON_PROPS" -gt 0 ]; then
    echo "  ❌ Found $OLD_JACKSON_PROPS old Jackson property names"
else
    echo "  ✅ No old Jackson property names found"
fi

echo "[6/8] Checking for Undertow references..."
UNDERTOW_COUNT=$(grep -r "undertow" src/ pom.xml build.gradle* 2>/dev/null | wc -l || true)
if [ "$UNDERTOW_COUNT" -gt 0 ]; then
    echo "  ❌ Found $UNDERTOW_COUNT Undertow references"
else
    echo "  ✅ No Undertow references found"
fi

echo "[7/8] Checking for public fields in @ConfigurationProperties..."
echo "  ⚠️  Manual review needed — search for @ConfigurationProperties classes with public fields"

echo "[8/8] Checking for WebSecurityConfigurerAdapter..."
WSCA_COUNT=$(grep -r "WebSecurityConfigurerAdapter" src/ --include="*.java" | wc -l || true)
if [ "$WSCA_COUNT" -gt 0 ]; then
    echo "  ❌ Found $WSCA_COUNT WebSecurityConfigurerAdapter references"
else
    echo "  ✅ No WebSecurityConfigurerAdapter found"
fi

echo ""
echo "=== Validation Complete ==="
echo "Run 'mvn clean test' or './gradlew clean test' to verify full build."
```

---

> **End of Playbook**
>
> Last updated: February 2026
> Based on: Spring Boot 4.0.0 GA, Java 25 (September 2025), Spring Framework 7.0
> Sources: Official Spring Boot 4.0 Migration Guide, Spring Boot 4.0 Release Notes, Java 25 Release Notes
