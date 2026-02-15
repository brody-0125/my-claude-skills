# SE Orchestration Protocol

> On-demand resource for Phase 1 (SE system detected). Defines agent selection matrix, 8 chain rules, dispatch protocol, and conflict resolution for the Security domain.

---

## 1. Agent Selection Matrix (Expanded)

Detailed keyword → agent mapping with rationale for all 6 clusters (A/Z/E/N/C/V), 24 agents total.

### Cluster A — Authentication (4 agents)

| Trigger Keywords | Agent | Rationale |
|-----------------|-------|-----------|
| authentication, oauth, oauth2, oidc, saml, sso, login flow, auth protocol, identity provider | a1-authn-flow-designer | Protocol selection requires understanding of federation standards and use-case fit |
| jwt, token, refresh token, access token, claims, token rotation, token storage, token blacklist | a2-token-strategist | Token lifecycle decisions affect security posture and performance |
| session, mfa, multi-factor, sso federation, stateless session, session fixation, session hijacking | a3-session-architect | Session design impacts scalability and security boundaries |
| bcrypt, argon2, scrypt, passkey, webauthn, passwordless, credential, password policy, fido | a4-credential-manager | Credential storage decisions are critical for breach resistance |

### Cluster Z — Authorization (4 agents)

| Trigger Keywords | Agent | Rationale |
|-----------------|-------|-----------|
| rbac, abac, rebac, access control model, permission model, multi-tenant authorization | z1-access-model-selector | Model selection determines entire authorization architecture |
| opa, cedar, casbin, policy engine, policy rule, policy evaluation, policy test, rego | z2-policy-designer | Policy engine design requires understanding of rule complexity and evaluation performance |
| least privilege, over-privilege, permission matrix, role explosion, permission audit, access review | z3-permission-auditor | Permission auditing is deterministic checklist verification |
| oauth scope, api permission, dynamic scope, consent management, token-permission mapping | z4-scope-architect | Scope design bridges authentication and authorization layers |

### Cluster E — Encryption & Key Management (4 agents)

| Trigger Keywords | Agent | Rationale |
|-----------------|-------|-----------|
| encryption, at-rest, in-transit, field-level, aes-256, chacha20, algorithm selection, crypto | e1-encryption-advisor | Encryption strategy requires understanding performance/security trade-offs |
| key rotation, key lifecycle, hsm, vault integration, kms, key escrow, key distribution | e2-key-lifecycle-planner | Key management lifecycle is critical infrastructure |
| tls, mtls, cipher suite, certificate chain, ocsp, certificate pinning, ssl termination | e3-tls-configurator | TLS configuration is deterministic best-practice application |
| secret management, hashicorp vault, aws secrets manager, secret rotation, dynamic secret, env var | e4-secret-manager | Secret management requires understanding of deployment topology |

### Cluster N — Network Security (4 agents)

| Trigger Keywords | Agent | Rationale |
|-----------------|-------|-----------|
| cors, csp, hsts, x-frame-options, referrer-policy, security header, permissions-policy | n1-header-hardener | Header configuration is deterministic checklist application |
| waf, rate limiting, ip filtering, ddos, geo-blocking, modsecurity, cloudflare, aws waf | n2-waf-rule-designer | WAF rule design requires understanding of attack patterns |
| api gateway, auth delegation, request validation, throttling, api key management, request signing | n3-api-gateway-security | API gateway security bridges network and application layers |
| sql injection, xss, path traversal, sanitization, input validation, content-type, file upload | n4-input-sanitizer | Input validation requires OWASP-aligned defense patterns |

### Cluster C — Compliance & Audit (4 agents)

| Trigger Keywords | Agent | Rationale |
|-----------------|-------|-----------|
| soc2, iso27001, gdpr, pci-dss, compliance framework, regulatory, trust services criteria | c1-compliance-mapper | Compliance mapping requires cross-framework knowledge |
| audit log, audit trail, event schema, append-only, worm, tamper detection, hash chain | c2-audit-trail-designer | Audit trail design affects data integrity and forensic capability |
| zero-trust, microsegmentation, device trust, beyondcorp, continuous verification, ztna | c3-zero-trust-planner | Zero-trust architecture requires holistic security design |
| gdpr data subject, consent management, pii detection, data masking, dpia, data retention | c4-privacy-engineer | Privacy engineering requires regulatory and technical expertise |

### Cluster V — Vulnerability & Threat (4 agents)

| Trigger Keywords | Agent | Rationale |
|-----------------|-------|-----------|
| stride, pasta, attack tree, threat scenario, attack surface, threat model, kill chain | v1-threat-modeler | Threat modeling requires structured methodology application |
| owasp top 10, injection, xss, auth flaw, ssrf, deserialization, security misconfiguration | v2-owasp-auditor | OWASP audit is systematic checklist-based evaluation |
| penetration test, black-box, white-box, gray-box, burp, zap, nuclei, pentest methodology | v3-pentest-strategist | Pentest strategy is deterministic scope/tool selection |
| sca, sbom, license compliance, cve monitoring, dependency vulnerability, sigstore, cosign | v4-supply-chain-auditor | Supply chain audit requires toolchain and process knowledge |

---

## 2. Chain Selection Algorithm

### Scoring Procedure

```
FOR each chain C in [Chain1..Chain8]:
  score[C] = count of C.trigger_keywords found in query (case-insensitive)

IF exactly 1 chain has score > 0:
  → Execute that chain

IF 2+ chains have score > 0:
  sorted = sort chains by score DESC

  # Superset check
  FOR each pair (X, Y) where score[X] >= score[Y]:
    IF X.agents ⊇ Y.agents:
      → Remove Y (subsumed by X)

  # If still 2+ chains after pruning:
  merged_agents = union(all remaining chains' agents)
  → Apply topological sort using dependency rules (§4)
  → Execute merged pipeline

IF 0 chains match:
  → Fall back to individual agent selection (§1)
```

### Precedence Order (Tiebreaking)

When two chains have equal scores and neither subsumes the other:
```
Chain 1 (8 agents, 종합) > Chain 4 (7 agents, 감사) > Chain 2 (7 agents, 인증) >
Chain 3 (5 agents, 인가) > Chain 5 (6 agents, ZT) > Chain 7 (5 agents, 프라이버시) >
Chain 6 (6 agents, 취약점) > Chain 8 (5 agents, SDL)
```

---

## 3. Chain Rules (Detailed Pipelines)

### Chain 1: New API Endpoint Security (종합 보안)

**Trigger**: "new api security", "secure endpoint", "api authentication", "api authorization"

```
Wave 1: A-1 (authn flow)
Wave 2: A-2 (token strategy, needs A-1)
Wave 3: Z-1 (access model) — parallel with Wave 2 if no A-2→Z overlap
Wave 4: Z-4 (scope, needs Z-1) + N-1 (headers, independent) — parallel
Wave 5: N-3 (api gateway) + N-4 (input sanitizer) — parallel
Wave 6: C-2 (audit trail, needs all above for complete picture)
```

**Output expectation**: Complete API security blueprint covering auth, authz, transport, input validation, and audit.

### Chain 2: Authentication System Design

**Trigger**: "auth system", "login design", "sso implementation", "mfa design", "passkey"

```
Wave 1: A-1 (authn flow selection)
Wave 2: A-2 (token strategy, needs A-1) + A-3 (session, needs A-1) — parallel
Wave 3: A-4 (credentials, needs A-1)
Wave 4: E-1 (encryption needs from A-2 token decisions)
Wave 5: E-2 (key lifecycle, needs E-1)
Wave 6: C-2 (audit trail for auth events)
```

### Chain 3: Authorization System Design

**Trigger**: "access control design", "permission system", "rbac implementation", "policy engine", "abac"

```
Wave 1: Z-1 (access model selection)
Wave 2: Z-2 (policy engine, needs Z-1) + Z-4 (scope design, needs Z-1) — parallel
Wave 3: Z-3 (permission audit, needs Z-1)
Wave 4: C-2 (audit trail for authz decisions, needs Z-2)
```

### Chain 4: Security Audit / Compliance Review

**Trigger**: "security audit", "compliance review", "soc2 preparation", "gdpr assessment", "pci-dss"

```
Wave 1: V-2 (OWASP audit) + C-1 (compliance mapping) — parallel
Wave 2: V-4 (supply chain, needs V-2) + C-2 (audit trail, needs C-1) — parallel
Wave 3: C-4 (privacy, needs C-1)
Wave 4: V-1 (threat model, informed by V-2 findings)
Wave 5: Z-3 (permission audit, informed by compliance requirements)
```

### Chain 5: Zero-Trust Implementation

**Trigger**: "zero trust", "zero-trust", "microsegmentation", "beyondcorp"

```
Wave 1: C-3 (zero-trust architecture)
Wave 2: A-1 (continuous authentication, needs C-3 architecture) + E-3 (mTLS, needs C-3) — parallel
Wave 3: E-4 (secret management for zero-trust) + N-2 (network policies) — parallel
Wave 4: Z-1 (access model aligned with zero-trust)
```

### Chain 6: Vulnerability Assessment

**Trigger**: "vulnerability assessment", "penetration test", "security testing", "threat analysis"

```
Wave 1: V-1 (threat modeling)
Wave 2: V-2 (OWASP audit, focus from V-1)
Wave 3: V-4 (supply chain audit, scope from V-2)
Wave 4: V-3 (pentest strategy, scope from V-2) + N-1 (header check) — parallel
Wave 5: C-2 (document findings in audit trail)
```

### Chain 7: Data Protection & Privacy

**Trigger**: "data protection", "privacy", "gdpr implementation", "pii", "data masking", "dpia"

```
Wave 1: C-4 (privacy requirements analysis)
Wave 2: E-1 (encryption strategy for data protection, needs C-4)
Wave 3: E-4 (secret management for PII) + C-2 (audit trail for data access) — parallel
Wave 4: C-1 (compliance framework verification)
```

### Chain 8: Secure Development Lifecycle (SDL)

**Trigger**: "secure development", "sdl", "security review", "code security", "sast", "dast", "devsecops"

```
Wave 1: V-2 (OWASP baseline audit)
Wave 2: N-4 (input validation patterns)
Wave 3: V-4 (supply chain / SCA)
Wave 4: C-2 (audit trail for SDL events) + V-3 (testing strategy) — parallel
```

---

## 4. Cross-Cluster Dependency Rules

### Intra-Cluster Dependencies

```
# Cluster A (Authentication)
A-1 → A-2   Auth flow selection determines token strategy
A-1 → A-3   Auth flow selection determines session design
A-1 → A-4   Auth flow influences credential management approach

# Cluster Z (Authorization)
Z-1 → Z-2   Access model determines policy engine design
Z-1 → Z-3   Access model determines audit scope
Z-1 → Z-4   Access model influences scope granularity

# Cluster E (Encryption)
E-1 → E-2   Encryption strategy determines key lifecycle requirements
E-1 → E-3   Encryption strategy informs TLS configuration choices
E-1 → E-4   Encryption strategy affects secret management approach

# Cluster N (Network Security)
N-1, N-2, N-3, N-4: all independent — parallel dispatch OK

# Cluster C (Compliance)
C-1 → C-4   Compliance framework determines privacy requirements scope
C-2, C-3: independent of other C agents — parallel dispatch OK

# Cluster V (Vulnerability)
V-1 → V-2   Threat model focuses OWASP evaluation areas
V-2 → V-3   Vulnerability findings scope penetration test
V-2 → V-4   OWASP results inform supply chain audit priorities
```

### Cross-Cluster Dependencies

```
A-2 → E-1   Token encryption needs (JWT signing, token encryption) feed encryption strategy
A-2 → Z-4   Token claim structure influences OAuth scope design
Z-2 → C-2   Policy decision logging feeds audit trail requirements
N-4 → V-2   Input validation gaps feed into OWASP vulnerability assessment
C-4 → E-1   Privacy requirements (PII encryption) drive encryption strategy
C-1 → C-4   Compliance framework determines privacy requirements scope
```

### Independent Pairs (Safe for Parallel Dispatch)

```
A cluster ↔ V cluster   Authentication design is independent of vulnerability assessment
N cluster ↔ C cluster   Network hardening is independent of compliance mapping (except C-2)
E cluster ↔ Z cluster   Encryption is independent of authorization model selection
```

### Topological Sort Example

Query: "Implement OAuth2 with RBAC and audit logging"
Matched agents: A-1, A-2, Z-1, Z-2, C-2

Dependency graph:
```
A-1 → A-2 → Z-4 (if selected)
Z-1 → Z-2 → C-2
A-1 (independent of Z-1)
```

Execution order:
```
Wave 1: A-1 + Z-1 (parallel, independent)
Wave 2: A-2 + Z-2 (parallel, each depends only on own cluster lead)
Wave 3: C-2 (depends on Z-2)
```

---

## 5. Reference Excerpt Extraction Procedure

Each agent's reference file has section markers. Extract only the relevant section.

| Agent | Reference File | Section |
|-------|---------------|---------|
| a1 | cluster-a-authentication.md | § OAuth2/OIDC/SAML Flow Patterns |
| a2 | cluster-a-authentication.md | § Token Lifecycle Patterns |
| a3 | cluster-a-authentication.md | § Session Management Patterns |
| a4 | cluster-a-authentication.md | § Credential Storage Patterns |
| z1 | cluster-z-authorization.md | § Access Control Models |
| z2 | cluster-z-authorization.md | § Policy Engine Patterns |
| z3 | cluster-z-authorization.md | § Permission Audit Patterns |
| z4 | cluster-z-authorization.md | § Scope Design Patterns |
| e1 | cluster-e-encryption.md | § Encryption Algorithms & Strategy |
| e2 | cluster-e-encryption.md | § Key Management Lifecycle |
| e3 | cluster-e-encryption.md | § TLS/mTLS Configuration |
| e4 | cluster-e-encryption.md | § Secret Management Patterns |
| n1 | cluster-n-network-security.md | § Security Headers |
| n2 | cluster-n-network-security.md | § WAF & Rate Limiting |
| n3 | cluster-n-network-security.md | § API Gateway Security |
| n4 | cluster-n-network-security.md | § Input Validation Patterns |
| c1 | cluster-c-compliance.md | § Compliance Frameworks |
| c2 | cluster-c-compliance.md | § Audit Trail Design |
| c3 | cluster-c-compliance.md | § Zero-Trust Architecture |
| c4 | cluster-c-compliance.md | § Privacy Engineering |
| v1 | cluster-v-vulnerability.md | § Threat Modeling Methodologies |
| v2 | cluster-v-vulnerability.md | § OWASP Top 10 Checklist |
| v3 | cluster-v-vulnerability.md | § Penetration Testing |
| v4 | cluster-v-vulnerability.md | § Supply Chain Security |

**Loading rules** (same as DB/BE):
- ≤200 lines: full Read
- 201-500 lines: offset/limit targeting agent's section
- >500 lines: Grep for section header, then Read with offset/limit

---

## 6. Parallel Dispatch Rules

| Scenario | Max Concurrent | Wave Strategy |
|----------|---------------|---------------|
| Single cluster, 1 agent | 1 | Direct dispatch |
| Single cluster, 2-4 agents | 3 | Respect intra-cluster deps |
| 2 clusters, independent | 3 | Both clusters Wave 1 |
| 2 clusters, dependent | 3 | Upstream cluster Wave 1, downstream Wave 2 |
| 3+ clusters | 3 | Topological sort → batched waves |
| Chain execution | 3 | Follow chain wave definitions (§3) |

---

## 7. Result Merge Algorithm

### Step 1: Collect

Gather all `agent_results[]` from dispatched agents.

### Step 2: Detect Conflicts

Compare recommendations across agents for:
- **Contradictory algorithms**: e.g., Agent A recommends AES-GCM, Agent B recommends ChaCha20
- **Incompatible architectures**: e.g., stateless JWT vs server-side session
- **Conflicting policies**: e.g., RBAC simplicity vs ABAC flexibility requirements
- **Resource conflicts**: e.g., Vault for secrets vs environment variables

### Step 3: Cross-Cluster Agreement

Verify that cross-dependent agents agree:
- A-2 token encryption aligns with E-1 encryption strategy
- Z-2 policy decisions are captured by C-2 audit trail
- N-4 validation rules address V-2 OWASP findings

### Step 4: Merge

Combine non-conflicting recommendations into `merged_recommendations[]`. Flag conflicts in `conflicts[]` for user resolution.

---

## 8. Conflict Resolution Protocol

### Step 1: Identify

List all conflicting recommendation pairs with agent names and clusters.

### Step 2: Present Trade-offs

For each conflict, provide:

| Option | Agent | Pros | Cons |
|--------|-------|------|------|
| Option A | agent-name | ... | ... |
| Option B | agent-name | ... | ... |

### Step 3: Apply Priority Rules (if no user preference)

```
Priority 1: User-specified constraints
Priority 2: Security correctness (defense-in-depth)
Priority 3: Compliance requirements (regulatory)
Priority 4: Authentication/Authorization integrity
Priority 5: Encryption strength
Priority 6: Network hardening
Priority 7: Operational feasibility
```

### Step 4: Document Resolution

Record in `conflicts[]`:
```json
{
  "agents": ["a2-token-strategist", "e1-encryption-advisor"],
  "field": "token_encryption",
  "option_a": "RSA-OAEP for JWT encryption",
  "option_b": "AES-256-GCM for symmetric JWT",
  "resolution": "RSA-OAEP selected for asymmetric key distribution advantage",
  "resolution_method": "priority_rule",
  "priority_applied": "Encryption strength"
}
```

---

## 9. Cross-System Constraint Propagation

SE agent outputs may declare constraints that affect DB, BE, or IF systems. These MUST be forwarded to the synthesizer via `cross_notes[]`.

| SE Agent | Constraint Type | Target System | Example |
|----------|----------------|---------------|---------|
| e1 | encryption-at-rest | DB | "Storage engine must support TDE or column-level encryption" |
| c2 | audit-schema | DB | "Audit table requires who/what/when/where columns with hash chain" |
| a1 | auth-middleware | BE | "Spring Security OAuth2 Resource Server filter required" |
| z1 | authz-annotation | BE | "@PreAuthorize with SpEL for method-level RBAC" |
| n4 | validation-rules | BE | "Jakarta Validation annotations on all controller DTOs" |
| e3 | tls-termination | IF | "TLS 1.3 required at load balancer, mTLS for inter-service" |
| n2 | waf-config | IF | "AWS WAF managed rules for OWASP Top 10" |
| c3 | network-policy | IF | "Kubernetes NetworkPolicy for microsegmentation" |
