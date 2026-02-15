# SE Security Best Practices Reference

> Cross-cutting security patterns referenced by all SE agents

---

## 1. Defense-in-Depth

### 1.1 Layer Model

No single control is sufficient. Defense-in-depth layers independent controls
so that a failure in one layer does not compromise the system.

| Layer | Controls | Examples |
|-------|----------|---------|
| Perimeter | WAF, DDoS protection, geo-blocking, bot management | AWS Shield, Cloudflare, AWS WAF |
| Network | Segmentation, firewall rules, mTLS, VPN | K8s NetworkPolicy, Istio, VPC security groups |
| Application | Input validation, authentication, authorization, CSRF protection | Spring Security, OPA, custom middleware |
| Data | Encryption at rest/in transit, masking, tokenization, access control | AES-256-GCM, AWS KMS, HashiCorp Vault |
| Monitoring | Logging, alerting, anomaly detection, incident response | ELK/OpenSearch, PagerDuty, Falco, SIEM |

### 1.2 Principle of Least Privilege

Apply least privilege across every dimension of the system:

| Dimension | Application | Example |
|-----------|-------------|---------|
| Users | Grant minimum role required | Viewer role by default, escalate to Editor on request |
| Services | Scope IAM policies to specific resources and actions | `s3:GetObject` on specific bucket, not `s3:*` |
| Network | Default-deny with explicit allow rules | K8s NetworkPolicy deny-all + per-service ingress |
| Data | Column-level and row-level access | PostgreSQL RLS, application-layer field filtering |
| Time | Just-in-time access with automatic expiry | Temporary credentials (STS), time-bound access tokens |

#### IAM Policy (Least Privilege)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::my-app-uploads/users/${aws:PrincipalTag/user_id}/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-server-side-encryption": "AES256"
        }
      }
    }
  ]
}
```

---

## 2. Secure Design Principles

These principles, originally formulated by Saltzer and Schroeder (1975),
remain the foundation of secure system design.

| Principle | Description | Application |
|-----------|-------------|-------------|
| Fail Secure | System defaults to a secure state on failure | Deny access if auth service is unreachable |
| Complete Mediation | Every access request is checked, every time | No caching of authorization decisions beyond token TTL |
| Economy of Mechanism | Keep security mechanisms as simple as possible | Prefer well-tested libraries over custom crypto |
| Open Design | Security does not depend on secrecy of design | Use public algorithms (AES, RSA), not proprietary encryption |
| Separation of Privilege | Require multiple conditions for access | MFA (something you know + something you have) |
| Least Common Mechanism | Minimize shared resources between subjects | Separate databases per tenant, isolated process pools |
| Psychological Acceptability | Security mechanisms should be usable | SSO reduces password fatigue, passkeys over passwords |
| Defense in Depth | Multiple independent layers of protection | WAF + input validation + parameterized queries |

### Fail Secure Pattern

```kotlin
fun authorize(request: HttpServletRequest): AuthorizationResult {
    return try {
        val token = extractToken(request)
        val claims = tokenValidator.validate(token)
        val permissions = permissionService.getPermissions(claims.subject)
        AuthorizationResult.allowed(permissions)
    } catch (e: TokenExpiredException) {
        AuthorizationResult.denied("Token expired")
    } catch (e: Exception) {
        // FAIL SECURE: any unexpected error results in denial
        logger.error("Authorization failed unexpectedly", e)
        AuthorizationResult.denied("Authorization unavailable")
    }
}
```

### Separation of Privilege: Multi-Factor Example

```kotlin
@PostMapping("/admin/dangerous-action")
fun dangerousAction(
    @AuthenticationPrincipal user: UserPrincipal,
    @RequestHeader("X-MFA-Token") mfaToken: String,
    @RequestHeader("X-Approval-Token") approvalToken: String
): ResponseEntity<*> {
    // Factor 1: Session authentication (already verified by filter)
    // Factor 2: MFA verification
    require(mfaService.verify(user.id, mfaToken)) { "MFA verification failed" }
    // Factor 3: Approval from another authorized user
    require(approvalService.verify(approvalToken)) { "Dual-control approval required" }

    return performAction()
}
```

---

## 3. Security Architecture Patterns

### 3.1 API Security Checklist

| Area | Check | Priority |
|------|-------|----------|
| Authentication | OAuth2/OIDC with short-lived tokens (<1 hour) | Critical |
| Authorization | Resource-level checks on every endpoint | Critical |
| Input Validation | Schema validation (OpenAPI), type coercion prevention | Critical |
| Rate Limiting | Per-user and per-IP limits with 429 responses | High |
| Error Handling | Generic error messages, no stack traces in production | High |
| Transport | HTTPS only, HSTS, TLS 1.2+ | Critical |
| CORS | Explicit origin whitelist, no wildcard with credentials | High |
| Security Headers | CSP, X-Content-Type-Options, Referrer-Policy | Medium |
| Logging | Log auth events, access failures, mutations | High |
| Versioning | Deprecate insecure versions, sunset policy | Medium |

### 3.2 Microservice Security Patterns

#### API Gateway as Security Perimeter

```
Internet -> [WAF] -> [API Gateway] -> [Internal Services]
                     |
                     |- JWT validation
                     |- Rate limiting
                     |- Request logging
                     |- Header injection (X-Request-ID)
                     |- Schema validation
```

#### Service-to-Service mTLS

All internal traffic is encrypted and authenticated via mutual TLS.
The service mesh (Istio/Linkerd) handles certificate rotation transparently.

```yaml
# Istio PeerAuthentication: enforce mTLS for all services in namespace
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT
```

#### JWT Propagation Pattern

```
Client -> Gateway (validates JWT, extracts claims)
       -> X-User-ID: 123
       -> X-User-Roles: admin,editor
       -> Upstream Service (trusts gateway-injected headers)
```

The gateway is the single point of JWT validation. Upstream services
trust the gateway-injected headers and do not re-validate the token.
This requires that upstream services are not directly accessible from
outside the mesh (enforce via NetworkPolicy).

#### Centralized Auth Service

```
[Auth Service]
  |- POST /auth/token       (issue access + refresh tokens)
  |- POST /auth/refresh     (rotate tokens)
  |- POST /auth/revoke      (revoke tokens)
  |- GET  /auth/userinfo    (token introspection)
  |- GET  /auth/.well-known/jwks.json  (public keys)
```

### 3.3 Database Security Patterns

| Pattern | Implementation | Purpose |
|---------|---------------|---------|
| Connection Encryption | `sslmode=verify-full` in connection string | Prevent eavesdropping |
| Credential Rotation | Vault dynamic secrets (TTL: 1 hour) | Limit credential exposure window |
| Row-Level Security | PostgreSQL RLS policies | Multi-tenant data isolation |
| Query Parameterization | PreparedStatement / named parameters | SQL injection prevention |
| Audit Logging | pgAudit extension, application-level audit trail | Compliance, forensics |
| Backup Encryption | AES-256 encrypted backups, encrypted snapshots | Data protection at rest |
| Connection Pooling | PgBouncer / HikariCP with connection limits | Prevent connection exhaustion |

#### PostgreSQL Row-Level Security

```sql
-- Enable RLS on the table
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- Policy: users can only see their own orders
CREATE POLICY user_isolation ON orders
    USING (tenant_id = current_setting('app.current_tenant')::uuid);

-- Set tenant context per connection
SET app.current_tenant = 'tenant-uuid-here';
```

#### Vault Dynamic Database Credentials

```hcl
# Vault configuration for dynamic PostgreSQL credentials
resource "vault_database_secret_backend_role" "app_readonly" {
  backend = vault_mount.db.path
  name    = "app-readonly"
  db_name = vault_database_secret_backend_connection.postgres.name

  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';",
    "GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";",
  ]

  revocation_statements = [
    "DROP ROLE IF EXISTS \"{{name}}\";",
  ]

  default_ttl = 3600   # 1 hour
  max_ttl     = 86400  # 24 hours
}
```

---

## 4. Incident Response

### 4.1 NIST IR Framework (SP 800-61)

| Phase | Activities | Key Outputs |
|-------|-----------|-------------|
| **Preparation** | IR plan, team formation, tool setup, training, communication templates | IR playbook, contact list, forensic toolkit |
| **Detection & Analysis** | Alert triage, severity classification, scope determination, evidence collection | Incident ticket, timeline, IOCs |
| **Containment** | Short-term (isolate affected systems), long-term (patch, rebuild) | Containment actions log |
| **Eradication** | Remove malware, close vulnerabilities, patch systems | Eradication confirmation |
| **Recovery** | Restore from clean backups, validate integrity, gradual reconnection | Recovery validation report |
| **Post-Incident** | Lessons learned, IR plan update, control improvement | Post-mortem document |

### 4.2 Security Event Classification

| Severity | Description | Response Time | Escalation |
|----------|-------------|---------------|------------|
| P1 - Critical | Active data breach, system compromise, ransomware | 15 minutes | CISO, Legal, CEO immediately |
| P2 - High | Confirmed vulnerability exploitation, unauthorized access | 1 hour | Security Lead, Engineering VP |
| P3 - Medium | Suspicious activity, policy violation, failed attack | 4 hours | Security team on-call |
| P4 - Low | Informational, policy reminder, minor misconfiguration | Next business day | Security team queue |

#### Escalation Matrix

```yaml
escalation:
  p1_critical:
    - security_oncall: immediate
    - security_lead: 5_minutes
    - engineering_vp: 15_minutes
    - ciso: 15_minutes
    - legal: 30_minutes
    - external_ir_firm: 1_hour    # If needed
    - regulators: 72_hours        # GDPR Art. 33

  p2_high:
    - security_oncall: immediate
    - security_lead: 30_minutes
    - engineering_vp: 2_hours

  p3_medium:
    - security_oncall: immediate
    - security_lead: next_standup

  p4_low:
    - security_queue: next_business_day
```

#### Communication Template (Breach Notification)

```markdown
## Security Incident Notification

**Incident ID**: INC-2024-001
**Severity**: P1 - Critical
**Status**: Active / Contained / Resolved

### Summary
[Brief description of the incident]

### Timeline
- [HH:MM UTC] Detection: [How was it detected?]
- [HH:MM UTC] Triage: [Initial assessment]
- [HH:MM UTC] Containment: [Actions taken]

### Impact
- **Systems affected**: [List]
- **Data potentially exposed**: [Types and volume]
- **Users affected**: [Count and segments]

### Actions Taken
1. [Action 1]
2. [Action 2]

### Next Steps
- [ ] [Pending action 1]
- [ ] [Pending action 2]

### Contact
Security Team: security@example.com | +82-10-XXXX-XXXX
```

#### Post-Mortem Process

| Step | Activity | Responsible |
|------|----------|-------------|
| 1 | Schedule blameless post-mortem within 3 business days | Security Lead |
| 2 | Prepare timeline with evidence | Incident Commander |
| 3 | Identify root cause and contributing factors | Full team |
| 4 | Define action items with owners and deadlines | Full team |
| 5 | Publish post-mortem internally | Security Lead |
| 6 | Track action items to completion | Project Manager |
| 7 | Verify effectiveness of remediation | Security team |

---

## 5. Security Testing Integration

### 5.1 Shift-Left Security

Integrate security testing as early as possible in the development lifecycle.
Each stage adds a layer of confidence without slowing delivery.

| Stage | Tool Category | Tools | Blocking? |
|-------|-------------|-------|-----------|
| Pre-commit | Secret scanning | gitleaks, detect-secrets | Yes (hook) |
| Pre-commit | Linting | eslint-plugin-security, semgrep | Yes (hook) |
| CI Build | SAST | Semgrep, SonarQube, CodeQL | Yes (Critical/High) |
| CI Build | SCA | Trivy, Snyk, Dependabot | Yes (Critical) |
| CI Build | License check | license-finder, FOSSA | Yes (denied licenses) |
| CI Deploy | Container scan | Trivy, Grype | Yes (Critical/High) |
| CI Deploy | IaC scan | tfsec, Checkov, KICS | Yes (Critical) |
| Staging | DAST | OWASP ZAP, Nuclei | Advisory |
| Production | Runtime | Falco, WAF, SIEM | Alert + Block |
| Periodic | Pentest | Manual + automated | Report |

### 5.2 Tool Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│ Pre-commit                                                   │
│   gitleaks (secret scanning)                                 │
│   detect-secrets (additional patterns)                       │
│   semgrep --config=p/security-audit (quick SAST)            │
├─────────────────────────────────────────────────────────────┤
│ CI / Build                                                   │
│   Semgrep (full SAST ruleset)                               │
│   Trivy fs . (filesystem SCA)                               │
│   Snyk test (dependency vulnerabilities)                     │
│   license-finder (license compliance)                        │
├─────────────────────────────────────────────────────────────┤
│ CI / Deploy                                                  │
│   Trivy image (container vulnerability scan)                 │
│   cosign verify (image signature verification)               │
│   Checkov -d . (IaC security scan)                          │
│   OWASP ZAP baseline (quick DAST against staging)           │
├─────────────────────────────────────────────────────────────┤
│ Runtime / Production                                         │
│   Falco (runtime threat detection in K8s)                   │
│   AWS WAF + managed rules (L7 protection)                   │
│   CloudTrail + GuardDuty (AWS threat detection)             │
│   SIEM (log correlation and alerting)                        │
└─────────────────────────────────────────────────────────────┘
```

### 5.3 Pre-Commit Hook Configuration

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks

  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.4.0
    hooks:
      - id: detect-secrets
        args: ['--baseline', '.secrets.baseline']

  - repo: https://github.com/returntocorp/semgrep
    rev: v1.50.0
    hooks:
      - id: semgrep
        args: ['--config', 'p/security-audit', '--error']
```

### 5.4 CI/CD Security Gate (GitHub Actions)

```yaml
name: Security Gate
on: [pull_request]

jobs:
  sast:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Semgrep SAST
        uses: returntocorp/semgrep-action@v1
        with:
          config: >-
            p/security-audit
            p/owasp-top-ten
            p/kotlin
          generateSarif: true

  sca:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Trivy vulnerability scan
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'fs'
          severity: 'CRITICAL,HIGH'
          exit-code: '1'

  container:
    runs-on: ubuntu-latest
    needs: [sast, sca]
    steps:
      - uses: actions/checkout@v4
      - name: Build image
        run: docker build -t app:${{ github.sha }} .
      - name: Trivy container scan
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: 'app:${{ github.sha }}'
          severity: 'CRITICAL,HIGH'
          exit-code: '1'

  iac:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Checkov IaC scan
        uses: bridgecrewio/checkov-action@master
        with:
          directory: infra/
          framework: terraform
          soft_fail: false
```
