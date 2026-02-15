# Migration Playbook Summary — Java 21 + Spring Boot 3 → Java 25 + Spring Boot 4

**Use this summary when prompt/token limits apply (e.g. 64k). For full rule text (find/replace, validate), open the full playbook and jump to the section.**

- **Full playbook:** [migration-playbook.md](migration-playbook.md) (same repo, same branch).
- **Rules:** Process in order. Apply only to application code and child POMs. Do NOT modify parent POMs.

---

## Execution Order

1. **Phase 1** — Sections 1–3 (Build, Java, Starters) → must compile.
2. **Phase 2** — Sections 4–5 (Jackson 2→3, Security) → must compile.
3. **Phase 3** — Section 6 (Testing) → tests must pass.
4. **Phase 4** — Sections 7–8 (Config, Removed APIs) → must compile.
5. **Phase 5** — Section 9 (Docker, CI/CD, Validation).
6. **Phase 6** — Conditionals C1–C7 only if the app uses those features.

**Scope (from issue):** If scope is not `full`, execute ONLY the sections listed for that scope. Skip others.

---

## Section 1 — Build Files & Parent POM

- **1.1** Maven: Replace java.version / maven.compiler.source|target / release 21 → 25 in pom.xml.
- **1.2** Gradle: sourceCompatibility/targetCompatibility 21 → 25; languageVersion 21 → 25.
- **1.3** Gradle: Ensure Gradle ≥ 8.14 (wrapper).
- **1.4** Maven: Ensure Maven ≥ 3.9.
- **1.5** Update parent POM reference in child pom.xml (version only; parent is external).
- **1.6** Parent POM config: reference only; resolve from GitHub Packages or Nexus per config.
- **1.7** Gradle: Update Spring Boot plugin version.
- **1.8** Remove spring-authorization-server.version override if present.
- **1.9** Remove executable/uber-JAR loader configuration.

---

## Section 2 — Java 25 & Language

- **2.1** (Optional) Unnamed variables: replace unused catch/lambda params with `_`.
- **2.2** Virtual threads: remove ReentrantLock pinning workarounds if present (Java 24+ unpins).
- **2.3** JVM flags: remove UseCompactObjectHeaders, UseZGenerationalGC, BiasedLocking; add EnableDynamicAgentLoading if agents used.
- **2.4** java.time serialization: migrate off Java serialization for java.time types if used.

---

## Section 3 — Modularized Starters

- **3.0** (Temporary) Classic starters option.
- **3.1** spring-boot-starter-web → webmvc.
- **3.2** spring-boot-starter-aop → aop.
- **3.3** Add test starters as needed.
- **3.4** Spring Batch starter split (batch vs batch-jdbc).
- **3.5** Apply full starter rename map from full playbook.

---

## Section 4 — Jackson 2 → 3

- **4.1** Package: com.fasterxml.jackson → tools.jackson.
- **4.2** Maven/Gradle: Jackson groupId → tools.jackson.
- **4.3** ObjectMapper → JsonMapper.
- **4.4** Spring Boot Jackson annotation renames.
- **4.5** Serializer/deserializer class renames.
- **4.6** ObjectMapperBuilder → JsonMapper.builder().
- **4.7** (Temporary) Jackson 2 fallback if needed.
- **4.8** Jackson module auto-discovery.

---

## Section 5 — Spring Security

- **5.1** Remove WebSecurityConfigurerAdapter; use SecurityFilterChain.
- **5.2** authorizeRequests() → authorizeHttpRequests().
- **5.3** Spring Security test dependency updates.
- **5.4** CSRF and security header updates.

---

## Section 6 — Testing

- **6.1** @MockBean → @MockitoBean, @SpyBean → @MockitoSpyBean.
- **6.2** MockitoTestExecutionListener removal.
- **6.3** JUnit 4 removal; use JUnit Jupiter only.
- **6.4** Remove JUnit 4 Maven/Gradle deps.
- **6.5** RestTestClient (new).
- **6.6** Testcontainers 2.0.

---

## Section 7 — Config Property Renames

- **7.1** Jackson: spring.jackson.read/write/datetime → spring.jackson.json.*.
- **7.2** @ConfigurationProperties: no public field binding; use accessors.
- **7.3** MongoDB property renames (see full playbook).
- **7.4** Tracing property updates.
- **7.5** PropertyMapper API change.

---

## Section 8 — Removed & Deprecated APIs

- **8.1** Undertow: remove; use Tomcat or Jetty.
- **8.2** Executable launch scripts: remove.
- **8.3** Spock: migrate to JUnit Jupiter.
- **8.4** Spring Session Hazelcast/MongoDB: move to community deps.
- **8.5** Spring JCL: remove explicit spring-jcl.
- **8.6** Auto-configuration class visibility: do not depend on public members.
- **8.7** Java 25 removed: Runtime.runFinalization(), Object.finalize(). Remove calls and overrides; remove controller endpoints that only demonstrate them (e.g. runFinalization, finalize). Remove demo methods and tests.

---

## Section 9 — Docker, CI/CD & Validation

- **9.1** Base image → eclipse-temurin:25-jre-noble (or equivalent).
- **9.2** GraalVM native image updates.
- **9.3** Servlet container compatibility.
- **9.4** CI/CD pipeline Java version and steps.
- **9.5** Compilation check.
- **9.6** Test suite.
- **9.7** Startup smoke test.
- **9.8** JSON serialization smoke test.
- **9.9** Performance baseline (optional).
- **9.10** Dependency audit.
- **9.11** Generate MIGRATION_SUMMARY.md.

---

## Conditionals (only if app uses feature)

- **C1** Hibernate 6→7 / JPA: Jakarta Persistence 3.2, merge() behavior, fetch, config, open-in-view.
- **C2** Spring Batch 5→6: in-memory default, RabbitRetryTemplateCustomizer.
- **C3** Observability: Micrometer 2 / Actuator 4, @OptionalParameter, HttpMessageConverters.
- **C4** Resilience: native @Retryable.
- **C5** API versioning.
- **C6** HTTP service clients (declarative).
- **C7** Null safety: JSpecify (JSR-305 migration).

---

## Appendices (in full playbook only)

- **A** Full import rewrite map (javax→jakarta, Jackson, etc.).
- **B** Property rename map.
- **C** OpenRewrite Maven/Gradle config and recipe tree.
- **D** Quick validation script.

---

**End of summary.** For exact find/replace patterns and validation steps, use [migration-playbook.md](migration-playbook.md).
