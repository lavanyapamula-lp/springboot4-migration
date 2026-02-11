# Copilot Instructions — Spring Boot 3 → 4 / Java 21 → 25 Migration

> **This file configures GitHub Copilot to be migration-aware across the entire repository.**
> Every suggestion, completion, chat response, and agent action will respect these rules.
> Place this file at `.github/copilot-instructions.md` in your repository root.
> Remove or archive this file once the migration is complete and validated.

---

## Project Context

This repository is **actively being migrated** from:

| Component        | From              | To                          |
|------------------|-------------------|-----------------------------|
| Java             | 21 LTS            | 25 LTS                      |
| Spring Boot      | 3.x               | 4.0.0                       |
| Spring Framework | 6.x               | 7.0                         |
| Jakarta EE       | 10                | 11 (Servlet 6.1)            |
| Jackson          | 2.x               | 3.x                         |
| Hibernate        | 6.x               | 7.x (JPA 3.2)              |
| Spring Security  | 6.x               | 7.0                         |
| Spring Batch     | 5.x               | 6.0                         |
| JUnit            | Jupiter 5.x       | Jupiter 6.x                 |
| Testcontainers   | 1.x               | 2.0                         |
| Build Tool       | [Maven/Gradle]    | Maven 3.9+ / Gradle 8.14+   |

**Migration playbook**: See `migration-playbook.md` in the project root for the full rule set.

---

## Global Rules — Apply to ALL Copilot Interactions

### NEVER generate or suggest code that uses:

```
- com.fasterxml.jackson.databind.*     (use tools.jackson.databind.*)
- com.fasterxml.jackson.core.*         (use tools.jackson.core.*)
- com.fasterxml.jackson.datatype.*     (use tools.jackson.datatype.*)
- com.fasterxml.jackson.dataformat.*   (use tools.jackson.dataformat.*)
- com.fasterxml.jackson.module.*       (use tools.jackson.module.*)
  EXCEPTION: com.fasterxml.jackson.annotation.* is UNCHANGED — keep as-is

- new ObjectMapper()                   (use JsonMapper.builder().build())
- Jackson2ObjectMapperBuilder          (use JsonMapper.builder())
- @JsonComponent                       (use @JacksonComponent)
- @JsonMixin                           (use @JacksonMixin)
- JsonObjectSerializer                 (use ObjectValueSerializer)
- JsonObjectDeserializer               (use ObjectValueDeserializer)

- @MockBean                            (use @MockitoBean)
- @SpyBean                             (use @MockitoSpyBean)
- MockitoTestExecutionListener         (use @ExtendWith(MockitoExtension.class))

- import org.junit.Test                (use org.junit.jupiter.api.Test)
- import org.junit.Before              (use org.junit.jupiter.api.BeforeEach)
- import org.junit.After               (use org.junit.jupiter.api.AfterEach)
- import org.junit.BeforeClass         (use org.junit.jupiter.api.BeforeAll)
- import org.junit.AfterClass          (use org.junit.jupiter.api.AfterAll)
- import org.junit.Ignore              (use org.junit.jupiter.api.Disabled)
- import org.junit.Assert              (use org.junit.jupiter.api.Assertions)
- @RunWith(SpringRunner.class)         (use @SpringBootTest or @ExtendWith)
- @RunWith(MockitoJUnitRunner.class)   (use @ExtendWith(MockitoExtension.class))

- WebSecurityConfigurerAdapter         (use SecurityFilterChain @Bean)
- .authorizeRequests()                 (use .authorizeHttpRequests())
- .antMatchers()                       (use .requestMatchers())
- .mvcMatchers()                       (use .requestMatchers())

- javax.annotation.Nullable            (use org.jspecify.annotations.Nullable)
- javax.annotation.Nonnull             (use org.jspecify.annotations.NonNull)
- org.springframework.lang.Nullable    (use org.jspecify.annotations.Nullable)
- org.springframework.lang.NonNull     (use org.jspecify.annotations.NonNull)

- @OptionalParameter (actuator)        (use @Nullable from org.jspecify.annotations)

- spring-boot-starter-web              (use spring-boot-starter-webmvc for MVC apps)
- spring-boot-starter-aop              (use spring-boot-starter-aspectj)
- Undertow in any form                 (removed — use Tomcat or Jetty)

- import javax.persistence.*           (use jakarta.persistence.*)
- import javax.servlet.*               (use jakarta.servlet.*)
- import javax.validation.*            (use jakarta.validation.*)
```

### ALWAYS use these patterns in new/modified code:

```
- Java version: 25 (source and target compatibility)
- Spring Boot version: 4.0.0
- Jackson: tools.jackson.* packages with JsonMapper.builder() pattern
- Testing: @MockitoBean, @MockitoSpyBean, JUnit Jupiter 6
- Security: SecurityFilterChain @Bean, .authorizeHttpRequests(), .requestMatchers()
- Null safety: org.jspecify.annotations.Nullable / NonNull
- Configuration binding: private fields + getters/setters (NO public field binding)
- Resilience: prefer @Retryable / @ConcurrencyLimit from Spring Framework 7
- HTTP clients: prefer @HttpServiceClient interface-based clients for new service calls
- API versioning: prefer @ApiVersion annotation for new versioned endpoints
```

---

## File-Specific Rules

### `pom.xml` / `build.gradle` / `build.gradle.kts`

```
When editing build files:
- Spring Boot parent/plugin version must be 4.0.0
- Java version must be 25
- Gradle version must be >= 8.14 or 9.x
- Maven version must be >= 3.9
- Jackson group IDs: tools.jackson.* (except jackson-annotations)
- Never add spring-boot-starter-web; use spring-boot-starter-webmvc
- Never add spring-boot-starter-aop; use spring-boot-starter-aspectj
- Never add Undertow dependencies
- Never add JUnit 4 or junit-vintage-engine
- For every main technology starter, ensure the corresponding test starter exists:
    spring-boot-starter-security     → also add spring-boot-starter-security-test (test scope)
    spring-boot-starter-webmvc       → also add spring-boot-starter-webmvc-test (test scope)
    spring-boot-starter-data-jpa     → also add spring-boot-starter-data-jpa-test (test scope)
    spring-boot-starter-data-mongodb → also add spring-boot-starter-data-mongodb-test (test scope)
    spring-boot-starter-data-redis   → also add spring-boot-starter-data-redis-test (test scope)
    spring-boot-starter-kafka        → also add spring-boot-starter-kafka-test (test scope)
    spring-boot-starter-actuator     → also add spring-boot-starter-actuator-test (test scope)
    (apply same pattern for all technology starters)
- Spring Batch: use spring-boot-starter-batch-jdbc if database metadata is needed
```

### `*.java` (Source Code)

```
When writing or modifying Java source files:
- Use Java 25 language features where appropriate:
    - Unnamed variables (_) for unused catch/lambda parameters
    - Flexible constructor bodies (statements before super())
    - Stream Gatherers for custom intermediate operations
    - Module import declarations for cleaner imports
    - Markdown JavaDoc (///) for new documentation
- Use text blocks (""") for multi-line strings
- Use records for immutable data carriers
- Use sealed classes/interfaces where inheritance should be restricted
- Use pattern matching in switch expressions
- Use virtual threads for I/O-bound concurrent work (Thread.ofVirtual())
- synchronized blocks are fine with virtual threads (pinning fixed in Java 24+)

Jackson configuration pattern:
    @Bean
    JsonMapper jacksonJsonMapper() {
        return JsonMapper.builder()
            .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)
            .addModule(new JavaTimeModule())
            .build();
    }

Security configuration pattern:
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

@ConfigurationProperties pattern (NO public fields):
    @ConfigurationProperties("app")
    public class AppProps {
        private String name;
        public String getName() { return name; }
        public void setName(String name) { this.name = name; }
    }
    // OR use records:
    @ConfigurationProperties("app")
    public record AppProps(String name, int timeout) {}

Resilience pattern (Spring Framework 7 native):
    @Retryable(includes = SomeException.class, maxAttempts = 3,
               backoff = @Backoff(delay = 500, multiplier = 2))
    @ConcurrencyLimit(5)
    public Result doWork() { ... }

Hibernate/JPA — always use the RETURNED entity from merge():
    entity = entityManager.merge(entity);  // CORRECT
    // NOT: entityManager.merge(entity); entity.setX(...);  // WRONG — entity still detached
```

### `*Test.java` / `*Tests.java` / `*IT.java` (Test Code)

```
When writing or modifying test files:
- Use JUnit Jupiter 6 annotations exclusively (org.junit.jupiter.api.*)
- Use @MockitoBean instead of @MockBean
- Use @MockitoSpyBean instead of @SpyBean
- Use @ExtendWith(MockitoExtension.class) for classes with @Mock or @Captor
- Use Assertions.* from org.junit.jupiter.api (not org.junit.Assert)
- Use assertThrows() instead of @Test(expected=...)
- Use @Disabled instead of @Ignore
- Use @BeforeEach/@AfterEach instead of @Before/@After
- Use @BeforeAll/@AfterAll instead of @BeforeClass/@AfterClass (methods must be static)
- Use @ParameterizedTest with @ValueSource/@CsvSource instead of Parameterized runner
- Consider RestTestClient for testing MVC endpoints (new in Boot 4)
- Testcontainers: use 2.0 API — check for renamed methods/classes

Test class template:
    @SpringBootTest
    class MyServiceTest {

        @MockitoBean
        private ExternalService externalService;

        @Autowired
        private MyService myService;

        @Test
        void shouldDoSomething() {
            when(externalService.call()).thenReturn(expectedResult);
            var result = myService.process();
            assertThat(result).isNotNull();
        }
    }

Standalone unit test template:
    @ExtendWith(MockitoExtension.class)
    class MyUnitTest {

        @Mock
        private SomeDependency dependency;

        @InjectMocks
        private MyService service;

        @Test
        void shouldHandleEdgeCase() {
            when(dependency.fetch()).thenReturn(null);
            assertThrows(IllegalStateException.class, () -> service.process());
        }
    }
```

### `application.properties` / `application.yml` / `application-*.properties`

```
When editing configuration files:
- Jackson properties use json sub-namespace:
    spring.jackson.json.read.<feature>=true/false     (NOT spring.jackson.read.*)
    spring.jackson.json.write.<feature>=true/false    (NOT spring.jackson.write.*)
    spring.jackson.json.datetime.<feature>=true/false (NOT spring.jackson.datetime.*)
- Jackson module auto-discovery is ON by default:
    spring.jackson.find-and-add-modules=true  (set false to register manually)
- Spring Batch runs in-memory by default; no automatic database metadata storage
- Never add Undertow properties (server.undertow.*)
- MongoDB properties may have been renamed — verify against Boot 4 docs
- Tracing properties may have been renamed — verify against Boot 4 docs
- Prefer spring.jpa.open-in-view=false for new configurations
```

### `Dockerfile` / `docker-compose*.yml`

```
When editing Docker files:
- Base image must use Java 25:
    eclipse-temurin:25-jre-noble     (preferred)
    amazoncorretto:25                (alternative)
    NEVER use openjdk:* images       (deprecated)
- Do not use executable jar launch scripts (removed):
    CORRECT:   ENTRYPOINT ["java", "-jar", "app.jar"]
    WRONG:     ENTRYPOINT ["./app.jar"]
- JVM flags to consider:
    -XX:+EnableDynamicAgentLoading   (only if runtime agents are attached)
    Compact object headers and generational ZGC are default — no flags needed
- For GraalVM native images, use GraalVM 25+
```

### `.github/workflows/*.yml` / `Jenkinsfile` / CI files

```
When editing CI/CD configuration:
- Java version: 25
- Distribution: temurin (preferred)
- Gradle: >= 8.14 or 9.x
- Maven: >= 3.9
- Example GitHub Actions:
    - uses: actions/setup-java@v4
      with:
        distribution: 'temurin'
        java-version: '25'
```

---

## Migration Phase Awareness

```
The migration follows these phases. Copilot should be aware of the current state
and not suggest patterns from a later phase if earlier phases are incomplete.

Phase 1: BUILD FILES        — pom.xml / build.gradle version bumps and starter changes
Phase 2: IMPORT REWRITES    — Jackson, Security, JPA, testing import changes
Phase 3: API CHANGES        — Code-level API migrations (Jackson config, Security config, etc.)
Phase 4: TEST FIXES         — @MockBean removal, JUnit 4 elimination, test starter additions
Phase 5: NEW FEATURES       — Optional adoption of @Retryable, @ApiVersion, @HttpServiceClient, JSpecify
Phase 6: DEPLOYMENT         — Dockerfile, CI/CD, JVM flags
Phase 7: VALIDATION         — Compile, test, smoke test, dependency audit

If a file still has old-style patterns (e.g., Jackson 2 imports), Copilot should:
1. Flag the old pattern in any suggestion or review
2. Suggest the migrated replacement
3. Not mix old and new patterns in the same file
```

---

## Code Review Rules

```
When Copilot is used for code review (PR reviews, inline suggestions):

FLAG as migration issues:
- Any import from com.fasterxml.jackson.* (except annotation package)
- Any use of @MockBean or @SpyBean
- Any JUnit 4 import or annotation
- Any use of ObjectMapper constructor (new ObjectMapper())
- Any use of WebSecurityConfigurerAdapter
- Any use of .authorizeRequests() or .antMatchers()
- Any public field in @ConfigurationProperties class
- Any reference to Undertow
- Any javax.* import (should be jakarta.*)
- Any Docker image reference with Java 21 or openjdk
- Any spring-boot-starter-web (should be spring-boot-starter-webmvc)
- Any spring-boot-starter-aop (should be spring-boot-starter-aspectj)
- Any spring.jackson.read.* or spring.jackson.write.* property (missing .json. segment)

SUGGEST when reviewing:
- Virtual thread adoption for I/O-bound blocking code
- Record types for DTOs and value objects
- Pattern matching in switch for type-checking logic
- Text blocks for multi-line strings (SQL, JSON templates, etc.)
- Unnamed variables for unused parameters
- @Retryable for methods with manual retry loops
- @HttpServiceClient for manual RestClient/WebClient wrapper interfaces
```

---

## Common Migration Pitfalls — Copilot Should Warn About

```
1. JACKSON 3 LOCALE SERIALIZATION: Locale serialization format changed in Jackson 3.
   If the code serializes/deserializes Locale objects, flag for manual testing.

2. HIBERNATE merge() RETURN VALUE: entityManager.merge(entity) returns a NEW managed
   instance. Code that calls merge() and then continues using the original variable
   has a bug. The original entity remains detached.

3. SPRING BATCH METADATA LOSS: Upgrading with spring-boot-starter-batch (not -jdbc)
   means batch job metadata is no longer persisted. Job restart after failure won't
   work without the -jdbc starter.

4. JACKSON MODULE AUTO-DISCOVERY: Jackson 3 auto-discovers ALL modules on classpath.
   This can cause unexpected behavior if multiple Jackson modules conflict.
   Flag if spring.jackson.find-and-add-modules is not explicitly set.

5. TEST STARTERS MISSING: If a test uses @DataJpaTest, @WebMvcTest, @WithMockUser,
   or similar slice test annotations, the corresponding test starter MUST be in
   the test dependencies. Missing test starters cause silent configuration failures.

6. JAVA TIME SERIALIZATION: Java serialization of java.time classes (LocalDate, etc.)
   is incompatible between JDK 21 and JDK 25. Flag any ObjectInputStream/
   ObjectOutputStream usage with java.time types.

7. VIRTUAL THREAD PINNING IS FIXED: If code has ReentrantLock workarounds specifically
   for virtual thread pinning, these are no longer necessary (fixed in Java 24+).
   Flag as candidates for simplification.
```

---

## Cleanup Checklist — Remove After Migration

```
After the migration is fully validated and deployed to production:
1. Delete this file (.github/copilot-instructions.md) or replace with
   standard project instructions
2. Archive migration-playbook.md
3. Remove any Jackson 2 fallback configuration
   (spring.http.converters.preferred-json-mapper=jackson2)
4. Remove spring-boot-starter-classic / spring-boot-starter-test-classic
   if used as temporary migration aids
5. Remove any TODO comments referencing "migration" or "Boot 4"
6. Update project README with new version requirements
```
