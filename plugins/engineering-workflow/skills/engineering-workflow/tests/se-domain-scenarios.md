# SE Domain Test Scenarios

> Test scenarios for Security domain classification, cluster detection, chain triggering, and cross-system integration.

---

## 1. Single-Cluster Scenarios

### Cluster A — Authentication

| Query | Expected Clusters | Chain | Confidence |
|-------|------------------|-------|------------|
| "how to implement OAuth2 with JWT token rotation" | A | - | >= 0.85 |
| "passkey WebAuthn implementation with session management" | A | - | >= 0.85 |
| "SSO federation with SAML 2.0 for enterprise" | A | - | >= 0.85 |
| "MFA design with TOTP and recovery codes" | A | Chain 2 | >= 0.85 |

### Cluster Z — Authorization

| Query | Expected Clusters | Chain | Confidence |
|-------|------------------|-------|------------|
| "RBAC vs ABAC for multi-tenant SaaS" | Z | - | >= 0.85 |
| "OPA policy engine with Cedar for authorization" | Z | - | >= 0.85 |
| "design permission system with role hierarchy" | Z | Chain 3 | >= 0.85 |
| "OAuth scope design for API permissions" | Z | - | >= 0.85 |

### Cluster E — Encryption

| Query | Expected Clusters | Chain | Confidence |
|-------|------------------|-------|------------|
| "AES-256 encryption at-rest with key rotation using Vault" | E | - | >= 0.85 |
| "mTLS configuration with certificate pinning" | E | - | >= 0.85 |
| "HashiCorp Vault secret management setup" | E | - | >= 0.85 |
| "key management lifecycle with HSM" | E | - | >= 0.85 |

### Cluster N — Network Security

| Query | Expected Clusters | Chain | Confidence |
|-------|------------------|-------|------------|
| "configure CSP headers and CORS policy for SPA" | N | - | >= 0.85 |
| "WAF rate limiting with IP filtering" | N | - | >= 0.85 |
| "API gateway security with request validation" | N | - | >= 0.85 |
| "SQL injection and XSS prevention patterns" | N | - | >= 0.85 |

### Cluster C — Compliance

| Query | Expected Clusters | Chain | Confidence |
|-------|------------------|-------|------------|
| "SOC2 compliance audit with GDPR data protection" | C | Chain 4 | >= 0.85 |
| "zero-trust microsegmentation architecture" | C | Chain 5 | >= 0.85 |
| "audit logging with tamper-proof hash chain" | C | - | >= 0.85 |
| "GDPR DPIA with PII masking and consent management" | C | Chain 7 | >= 0.85 |

### Cluster V — Vulnerability

| Query | Expected Clusters | Chain | Confidence |
|-------|------------------|-------|------------|
| "OWASP Top 10 vulnerability assessment with SBOM" | V | - | >= 0.85 |
| "STRIDE threat model with penetration test using Burp" | V | Chain 6 | >= 0.85 |
| "supply chain security with SCA and Sigstore" | V | - | >= 0.85 |
| "secure development lifecycle with SAST and DAST" | V | Chain 8 | >= 0.85 |

---

## 2. Multi-Cluster Scenarios

| Query | Expected Clusters | Chain(s) | Notes |
|-------|------------------|----------|-------|
| "implement zero-trust with mTLS and RBAC" | Z, E, C | Chain 5 | 3-cluster: AuthZ + Encryption + Compliance |
| "WAF rate limiting with SQL injection prevention and SAST" | N, V | Chain 8 | 2-cluster: Network + Vulnerability |
| "OAuth2 authentication with RBAC and audit logging" | A, Z, C | Chain 1 or 2+3 | 3-cluster: full auth stack |
| "encryption at-rest with compliance audit and secret management" | E, C | Chain 7 | 2-cluster: Encryption + Compliance |
| "OWASP audit with CSP headers and input validation" | N, V | Chain 6 | 2-cluster: Network + Vulnerability |
| "passkey with ABAC policy and GDPR consent" | A, Z, C | Chain 2+3 | 3-cluster: AuthN + AuthZ + Compliance |

---

## 3. Cross-System Scenarios

| Query | Expected Systems | SE Clusters | Notes |
|-------|-----------------|-------------|-------|
| "database encryption at rest with TLS for API" | DB, BE, SE | E | DB+BE+SE cross-system |
| "design multi-tenant schema with RBAC and API rate limiting" | DB, BE, SE | Z | 3-system with AuthZ |
| "Kubernetes network policy with zero-trust and mTLS" | IF, SE | E, C | IF+SE cross-system |
| "Spring Security OAuth2 with JWT and database session store" | DB, BE, SE | A | DB+BE+SE with AuthN |
| "API endpoint with input validation and WAF in CI/CD" | BE, IF, SE | N | BE+IF+SE with Network |

---

## 4. Chain Trigger Verification

### Chain 1: New API Endpoint Security
| Trigger Query | Expected Pipeline |
|--------------|-------------------|
| "secure new API endpoint with authentication and authorization" | A-1 → A-2 → Z-1 → Z-4 → N-1 → N-3 → N-4 → C-2 |

### Chain 2: Authentication System Design
| Trigger Query | Expected Pipeline |
|--------------|-------------------|
| "design login system with SSO and MFA" | A-1 → A-2 → A-3 → A-4 → E-1 → E-2 → C-2 |

### Chain 3: Authorization System Design
| Trigger Query | Expected Pipeline |
|--------------|-------------------|
| "implement RBAC permission system with policy engine" | Z-1 → Z-2 → Z-4 → Z-3 → C-2 |

### Chain 4: Security Audit / Compliance Review
| Trigger Query | Expected Pipeline |
|--------------|-------------------|
| "SOC2 preparation with security audit" | {V-2, C-1} → {V-4, C-2} → C-4 → V-1 → Z-3 |

### Chain 5: Zero-Trust Implementation
| Trigger Query | Expected Pipeline |
|--------------|-------------------|
| "implement zero-trust architecture with BeyondCorp" | C-3 → A-1 → E-3 → E-4 → N-2 → Z-1 |

### Chain 6: Vulnerability Assessment
| Trigger Query | Expected Pipeline |
|--------------|-------------------|
| "vulnerability assessment with penetration testing" | V-1 → V-2 → V-4 → V-3 → N-1 → C-2 |

### Chain 7: Data Protection & Privacy
| Trigger Query | Expected Pipeline |
|--------------|-------------------|
| "GDPR implementation with PII masking and data protection" | C-4 → E-1 → E-4 → C-2 → C-1 |

### Chain 8: Secure Development Lifecycle
| Trigger Query | Expected Pipeline |
|--------------|-------------------|
| "secure development lifecycle with SAST and DAST" | V-2 → N-4 → V-4 → C-2 → V-3 |

---

## 5. Edge Cases

| Query | Expected | Notes |
|-------|----------|-------|
| "SECURITY" | systems=["SE"], clusters=[] | Uppercase, system-level only |
| "implement security best practices" | systems=["SE"], clusters=[] | Generic SE, no specific cluster |
| "login page design" | systems=["SE"], clusters=["A"] | login triggers AuthN |
| "firewall rules for network" | systems=["SE"], clusters=["N"] | firewall triggers Network |
| "audit compliance governance" | systems=["SE"], clusters=["C"] | compliance triggers Compliance |
| "CVE monitoring vulnerability scanning" | systems=["SE"], clusters=["V"] | CVE triggers Vulnerability |

---

## 6. False Positive Guards

| Query | Should NOT Match | Reason |
|-------|-----------------|--------|
| "React component state management" | SE | No security keywords |
| "the login page is slow" | SE (only if "login" is in SE keywords) | Borderline — login may trigger AuthN |
| "grant permissions to database user" | SE (but may match Z via "permission") | Context is DB, not security |
| "certificate program enrollment" | SE (but may match E via "certificate") | "certificate" is ambiguous (academic vs TLS) |

---

## 7. Validation Commands

```bash
# Run all classification tests (includes SE scenarios)
bash tests/run-classification-tests.sh

# Individual SE queries
scripts/classify-query.sh "how to implement OAuth2 with JWT token rotation"
# Expected: systems=["SE"], se_clusters=["A"], confidence >= 0.85

scripts/classify-query.sh "RBAC vs ABAC for multi-tenant SaaS"
# Expected: systems=["SE"], se_clusters=["Z"], confidence >= 0.85

scripts/classify-query.sh "implement zero-trust with mTLS and RBAC"
# Expected: systems=["SE"], se_clusters=["Z","E","C"], confidence >= 0.85

scripts/classify-query.sh "database encryption at rest with TLS for API"
# Expected: systems=["DB","BE","SE"], se_clusters=["E"], confidence >= 0.60
```
