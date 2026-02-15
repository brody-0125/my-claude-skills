# SE Compliance Cluster Reference

> Reference material for agents C-1, C-2, C-3, C-4

## Table of Contents

| Section | Agent | Line Range |
|---------|-------|------------|
| Compliance Frameworks | c1-compliance-mapper | 20-110 |
| Audit Trail Design | c2-audit-trail-designer | 111-200 |
| Zero-Trust Architecture | c3-zero-trust-planner | 201-280 |
| Privacy Engineering | c4-privacy-engineer | 281-350 |

---

<!-- SECTION:c1-compliance-mapper:START -->

## 1. Compliance Frameworks

### 1.1 SOC2 Trust Services Criteria

SOC2 is organized around five Trust Services Categories (TSC).
Each category maps to specific Common Criteria (CC) controls.

| Category | Criteria Range | Focus |
|----------|---------------|-------|
| Security (Common Criteria) | CC1-CC9 | Logical and physical access, system operations, change management, risk mitigation |
| Availability | A1.1-A1.3 | System uptime, disaster recovery, capacity management |
| Processing Integrity | PI1.1-PI1.5 | Completeness, accuracy, timeliness of processing |
| Confidentiality | C1.1-C1.2 | Classification, protection of confidential information |
| Privacy | P1-P8 | Notice, consent, collection, use, retention, disclosure, access, quality |

#### Key CC Controls

| Control | Title | Evidence Examples |
|---------|-------|-------------------|
| CC1.1 | COSO Principle 1: Integrity & Ethics | Code of conduct, background checks |
| CC2.1 | Communication of objectives | Security policies, training records |
| CC3.1 | Risk assessment | Risk register, vulnerability scans |
| CC5.1 | Control activities over technology | Change management logs, CI/CD pipeline configs |
| CC6.1 | Logical access controls | IAM policies, MFA configuration, SSO setup |
| CC6.2 | Access provisioning | Onboarding/offboarding checklists, access reviews |
| CC6.3 | Access removal | Automated deprovisioning, termination workflow |
| CC6.7 | Data-in-transit encryption | TLS configuration, certificate management |
| CC7.1 | Monitoring infrastructure | SIEM dashboards, alert configuration |
| CC7.2 | Security event evaluation | Incident tickets, triage runbooks |
| CC7.3 | Incident response initiation | IR plan, communication templates |
| CC8.1 | Change management | PR reviews, deployment approvals, rollback procedures |
| CC9.1 | Risk mitigation activities | Vendor assessments, insurance documentation |

### 1.2 ISO 27001 Annex A Controls

ISO 27001:2022 Annex A contains 93 controls organized in 4 themes
(previously 14 domains in the 2013 version).

| Theme | Control Count | Key Areas |
|-------|--------------|-----------|
| Organizational (A.5) | 37 | Policies, roles, asset management, access control, supplier relationships |
| People (A.6) | 8 | Screening, awareness, disciplinary process, remote working |
| Physical (A.7) | 14 | Perimeters, equipment, secure disposal, clear desk |
| Technological (A.8) | 34 | Endpoint, privileged access, encryption, secure development, logging |

#### Critical Controls for Software Organizations

| Control ID | Title | Implementation |
|-----------|-------|----------------|
| A.5.1 | Policies for information security | Published security policy, annual review cycle |
| A.5.15 | Access control | RBAC implementation, principle of least privilege |
| A.5.23 | Information security for cloud services | Cloud security posture management (CSPM) |
| A.8.9 | Configuration management | Infrastructure as Code, drift detection |
| A.8.25 | Secure development lifecycle | SAST/DAST integration, secure code review |
| A.8.28 | Secure coding | Coding standards, dependency scanning |

#### Statement of Applicability (SoA)

The SoA documents each Annex A control with:
- Applicability status (applicable / not applicable)
- Justification for exclusion if not applicable
- Implementation status (implemented / partially / planned)
- Reference to implementing procedures

### 1.3 GDPR Key Articles

| Article | Title | Technical Implication |
|---------|-------|-----------------------|
| Art. 5 | Principles | Purpose limitation, data minimization, storage limitation, integrity |
| Art. 6 | Lawful basis | Consent management, legitimate interest assessment |
| Art. 7 | Conditions for consent | Granular opt-in, easy withdrawal mechanism |
| Art. 12-14 | Transparency | Privacy notice, data collection disclosure |
| Art. 15 | Right of access | Subject Access Request (SAR) API endpoint |
| Art. 16 | Right to rectification | Data update APIs |
| Art. 17 | Right to erasure | Cascading delete/anonymization pipeline |
| Art. 20 | Right to data portability | Machine-readable export (JSON/CSV) |
| Art. 25 | Data protection by design | Privacy impact assessments, encryption by default |
| Art. 30 | Records of processing | Processing activity register (automated) |
| Art. 32 | Security of processing | Encryption, pseudonymization, access controls, testing |
| Art. 33 | Breach notification to authority | 72-hour notification pipeline, severity classification |
| Art. 34 | Breach notification to data subjects | Communication templates, affected user identification |
| Art. 35 | DPIA | Mandatory for high-risk processing |

### 1.4 PCI-DSS v4.0 Requirements

| Requirement | Title | Key Controls |
|------------|-------|--------------|
| Req 1 | Network security controls | Firewall rules, DMZ, microsegmentation |
| Req 2 | Secure configurations | Hardened images, CIS benchmarks |
| Req 3 | Protect stored account data | Encryption at rest (AES-256), key management |
| Req 4 | Protect data in transit | TLS 1.2+, certificate pinning |
| Req 5 | Anti-malware | Endpoint protection, container scanning |
| Req 6 | Secure development | Secure SDLC, code review, SAST |
| Req 7 | Restrict access by business need | RBAC, need-to-know enforcement |
| Req 8 | Identify users and authenticate | MFA, password policies, service accounts |
| Req 9 | Restrict physical access | Physical security (data centers) |
| Req 10 | Log and monitor | Centralized logging, SIEM, log integrity |
| Req 11 | Test security regularly | Vulnerability scanning (quarterly), penetration testing (annual) |
| Req 12 | Organizational policies | Incident response plan, security awareness training |

### 1.5 Cross-Framework Control Mapping

| Control Area | SOC2 | ISO 27001 | GDPR | PCI-DSS |
|-------------|------|-----------|------|---------|
| Access Control | CC6.1-CC6.3 | A.5.15, A.8.3 | Art. 32 | Req 7-8 |
| Encryption at Rest | CC6.1 | A.8.24 | Art. 32 | Req 3 |
| Encryption in Transit | CC6.7 | A.8.24 | Art. 32 | Req 4 |
| Audit Logging | CC7.1-CC7.2 | A.8.15 | Art. 30 | Req 10 |
| Incident Response | CC7.3-CC7.5 | A.5.24-A.5.28 | Art. 33-34 | Req 12.10 |
| Change Management | CC8.1 | A.8.32 | - | Req 6 |
| Vulnerability Management | CC3.1, CC7.1 | A.8.8 | Art. 32 | Req 5, 11 |
| Data Classification | C1.1 | A.5.12-A.5.13 | Art. 5 | Req 3 |
| Vendor Management | CC9.1 | A.5.19-A.5.22 | Art. 28 | Req 12.8 |
| Training & Awareness | CC1.4 | A.6.3 | Art. 39 | Req 12.6 |

<!-- SECTION:c1-compliance-mapper:END -->
<!-- SECTION:c2-audit-trail-designer:START -->

## 2. Audit Trail Design

### 2.1 Event Schema (W5 Model)

Every audit event must answer five questions: Who, What, When, Where, Why.

```json
{
  "event_id": "01HQXG5K3N7MJRS0P4VBCXW8KN",
  "event_version": "1.0",
  "timestamp": "2024-01-15T10:30:00.000Z",
  "actor": {
    "id": "user-123",
    "type": "user",
    "email": "alice@example.com",
    "ip": "192.168.1.100",
    "user_agent": "Mozilla/5.0...",
    "session_id": "sess-abc-456",
    "auth_method": "sso"
  },
  "action": {
    "type": "update",
    "category": "data_modification",
    "description": "Updated order shipping address"
  },
  "resource": {
    "type": "order",
    "id": "order-456",
    "attributes": {
      "order_number": "ORD-2024-001"
    }
  },
  "changes": {
    "before": {"shipping_address": "123 Old St"},
    "after": {"shipping_address": "456 New Ave"}
  },
  "result": {
    "status": "success",
    "http_status": 200
  },
  "context": {
    "service": "order-service",
    "version": "2.3.1",
    "environment": "production",
    "request_id": "req-789-xyz",
    "correlation_id": "corr-001"
  },
  "integrity": {
    "prev_hash": "sha256:abc123...",
    "hash": "sha256:def456..."
  }
}
```

#### Action Categories

| Category | Examples | Retention Priority |
|----------|---------|-------------------|
| `authentication` | login, logout, mfa_challenge | High |
| `authorization` | permission_grant, role_change | High |
| `data_creation` | record_create, file_upload | Medium |
| `data_modification` | record_update, field_change | High |
| `data_deletion` | record_delete, purge | Critical |
| `data_access` | record_view, export, download | Medium |
| `configuration` | setting_change, feature_toggle | High |
| `administrative` | user_provision, system_restart | High |

### 2.2 Immutability Patterns

#### Hash Chain

Each event includes a SHA-256 hash of the previous event, forming a
tamper-evident chain. Any modification to a historical event breaks
the chain from that point forward.

```python
import hashlib
import json

def compute_event_hash(event: dict, prev_hash: str) -> str:
    canonical = json.dumps(event, sort_keys=True, separators=(',', ':'))
    payload = f"{prev_hash}|{canonical}"
    return f"sha256:{hashlib.sha256(payload.encode()).hexdigest()}"
```

#### Append-Only Storage

| Storage | Mechanism | Cost |
|---------|-----------|------|
| S3 + Object Lock (Compliance Mode) | WORM — cannot be deleted even by root | $$ |
| PostgreSQL + restricted grants | `GRANT INSERT, SELECT ON audit_log TO audit_writer` (no UPDATE/DELETE) | $ |
| Amazon QLDB | Built-in immutable journal with cryptographic verification | $$$ |
| Elasticsearch with ILM | Write-once index policy, periodic snapshots | $$ |

#### Merkle Tree for Batch Verification

For high-volume systems, compute a Merkle root over batches of events
(e.g., every 1000 events or every hour). Store the Merkle root in a
separate tamper-proof ledger for periodic integrity verification.

```
          Root Hash
         /         \
    Hash(0-499)   Hash(500-999)
      /    \         /    \
   H(0-249) H(250-499) H(500-749) H(750-999)
    ...        ...        ...        ...
```

### 2.3 Retention Policy Matrix

| Regulation | Minimum Retention | Maximum Retention | Notes |
|------------|------------------|-------------------|-------|
| SOC2 | 1 year | No explicit max | Trust Services Criteria CC7.1 |
| PCI-DSS | 1 year (3 months immediately accessible) | No explicit max | Req 10.7 |
| GDPR | Purpose-limited | Must delete when no longer necessary | Balancing test required |
| HIPAA | 6 years | No explicit max | From date of creation or last effective date |
| SOX | 7 years | No explicit max | Financial records |
| Internal baseline | 2 years | 5 years | Recommended default policy |

#### Tiered Storage Strategy

```yaml
retention:
  hot_storage:         # Elasticsearch / PostgreSQL
    duration: 90d
    query_latency: <100ms

  warm_storage:        # S3 Standard
    duration: 365d
    query_latency: <5s
    compression: gzip

  cold_storage:        # S3 Glacier
    duration: 2555d    # 7 years
    query_latency: <12h
    encryption: AES-256
    object_lock: compliance
```

<!-- SECTION:c2-audit-trail-designer:END -->
<!-- SECTION:c3-zero-trust-planner:START -->

## 3. Zero-Trust Architecture

### 3.1 Core Principles

| Principle | Description | Implementation |
|-----------|-------------|----------------|
| Never trust, always verify | Every request is authenticated and authorized regardless of source | Token validation on every call |
| Least privilege access | Grant minimum permissions for minimum duration | Just-in-time access, short-lived tokens |
| Assume breach | Design as if attackers are already inside | Microsegmentation, encryption everywhere |
| Verify explicitly | Authenticate using all available data points | Device posture + identity + location + behavior |
| Continuous monitoring | Re-evaluate trust continuously | Session anomaly detection, step-up auth |

### 3.2 Microsegmentation Patterns

#### Kubernetes NetworkPolicy: Default Deny

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

#### Allow Specific Traffic

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-order-service
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: order-service
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api-gateway
      ports:
        - protocol: TCP
          port: 8080
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: postgres
      ports:
        - protocol: TCP
          port: 5432
    - to:                     # DNS resolution
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
```

#### Service Mesh mTLS (Istio)

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: strict-mtls
  namespace: production
spec:
  mtls:
    mode: STRICT
```

#### VPC Security Groups (Terraform)

```hcl
resource "aws_security_group" "app" {
  name_prefix = "app-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]  # Only from ALB
  }

  egress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.database.id]  # Only to DB
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # HTTPS to external services
  }
}
```

### 3.3 BeyondCorp Model

| Component | Purpose | Implementation |
|-----------|---------|----------------|
| Identity-Aware Proxy (IAP) | Authenticate every request before reaching application | Google IAP, AWS Verified Access |
| Device Trust | Score device security posture | Certificate presence, OS patch level, disk encryption |
| Access Tiers | Grant access based on combined signals | Tier 1: Any device + MFA; Tier 2: Managed device + MFA; Tier 3: Compliant device + hardware key |
| Context Engine | Evaluate risk signals in real-time | Location, time, behavior pattern, device health |
| Session Management | Continuous session evaluation | Re-authenticate on context change (new IP, location) |

#### Access Decision Flow

```
Request -> Identity (Who?) -> Device Trust (What device?)
       -> Context (Where/When?) -> Policy Engine (Allow/Deny/Step-up?)
       -> Application
```

### 3.4 Implementation Phases

| Phase | Actions | Duration | Success Criteria |
|-------|---------|----------|-----------------|
| 1. Visibility | Asset inventory, data flow mapping, identify protect surfaces | 2-4 weeks | Complete inventory of all services, data stores, access paths |
| 2. Identity | Deploy SSO + MFA, service account management, certificate management | 4-8 weeks | 100% of users on SSO+MFA, all service accounts inventoried |
| 3. Segmentation | Default-deny network policies, service mesh, database isolation | 6-12 weeks | All namespaces have NetworkPolicies, mTLS enabled |
| 4. Continuous | Anomaly detection, automated response, policy-as-code | Ongoing | MTTR < 1 hour for policy violations, automated remediation |

<!-- SECTION:c3-zero-trust-planner:END -->
<!-- SECTION:c4-privacy-engineer:START -->

## 4. Privacy Engineering

### 4.1 DPIA Process (Data Protection Impact Assessment)

#### Step-by-Step

| Step | Activity | Output |
|------|----------|--------|
| 1. Screening | Determine if DPIA is mandatory (Art. 35 criteria) | Screening checklist |
| 2. Description | Document processing purpose, scope, data flows | Data flow diagram |
| 3. Necessity | Assess necessity and proportionality | Lawful basis analysis |
| 4. Risk Assessment | Identify and score privacy risks | Risk register |
| 5. Mitigation | Define measures to reduce risks | Control mapping |
| 6. Sign-off | DPO review and management approval | Signed DPIA report |
| 7. Consultation | Consult supervisory authority if high risk remains | DPA submission (if needed) |

#### Mandatory DPIA Triggers

- Large-scale processing of special category data
- Systematic monitoring of public areas
- Automated decision-making with legal effects (profiling)
- Large-scale processing of children's data
- Innovative use of new technologies
- Data matching or combining from multiple sources

### 4.2 Data Subject Rights Implementation

#### SAR (Subject Access Request) API

```kotlin
@RestController
@RequestMapping("/api/v1/privacy")
class DataSubjectRightsController(
    private val sarService: SubjectAccessRequestService,
    private val erasureService: DataErasureService,
    private val exportService: DataExportService
) {
    @PostMapping("/sar")
    fun createSAR(
        @AuthenticationPrincipal user: UserPrincipal,
        @Valid @RequestBody request: SARRequest
    ): ResponseEntity<SARResponse> {
        // Verify identity (enhanced verification for SAR)
        require(request.verificationToken != null) { "Identity verification required" }

        val sar = sarService.initiate(
            userId = user.id,
            scope = request.scope,  // ALL, SPECIFIC_CATEGORY
            format = request.format  // JSON, CSV, PDF
        )
        // Must respond within 30 days (GDPR Art. 12(3))
        return ResponseEntity.accepted().body(SARResponse(
            requestId = sar.id,
            estimatedCompletion = sar.deadline,
            statusUrl = "/api/v1/privacy/sar/${sar.id}/status"
        ))
    }

    @DeleteMapping("/erasure")
    fun requestErasure(
        @AuthenticationPrincipal user: UserPrincipal,
        @Valid @RequestBody request: ErasureRequest
    ): ResponseEntity<ErasureResponse> {
        val result = erasureService.initiate(
            userId = user.id,
            scope = request.scope,
            retainForLegal = request.acknowledgeRetention
        )
        return ResponseEntity.accepted().body(result)
    }

    @GetMapping("/export")
    fun exportData(
        @AuthenticationPrincipal user: UserPrincipal,
        @RequestParam format: ExportFormat
    ): ResponseEntity<Resource> {
        val export = exportService.generate(user.id, format)
        return ResponseEntity.ok()
            .contentType(MediaType.APPLICATION_OCTET_STREAM)
            .header("Content-Disposition", "attachment; filename=\"my-data.${format.extension}\"")
            .body(export)
    }
}
```

#### Right to Erasure: Cascading Pipeline

```yaml
erasure_pipeline:
  steps:
    - service: user-service
      action: anonymize_profile
      fields: [name, email, phone, address]
      method: irreversible_hash

    - service: order-service
      action: anonymize_orders
      retain: [order_id, total, date]  # Financial records retention
      anonymize: [shipping_address, customer_name]

    - service: analytics-service
      action: delete_raw_events
      retain_aggregates: true  # Keep anonymized aggregates

    - service: email-service
      action: delete_all_communications

    - service: storage-service
      action: delete_uploads
      bucket: user-uploads
      prefix: "users/{user_id}/"

    - service: search-service
      action: remove_from_index

  verification:
    method: spot_check
    sample_size: 100
    frequency: monthly
```

### 4.3 PII Detection & Masking

#### Regex Patterns for Common PII

| PII Type | Regex Pattern | Example |
|----------|--------------|---------|
| Email | `[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}` | user@example.com |
| Phone (US) | `(\+1)?[\s.-]?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}` | +1 (555) 123-4567 |
| SSN | `\d{3}-\d{2}-\d{4}` | 123-45-6789 |
| Credit Card | `\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}` | 4111-1111-1111-1111 |
| IP Address | `\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}` | 192.168.1.1 |
| Date of Birth | `\d{4}-\d{2}-\d{2}` (with context) | 1990-01-15 |
| Korean RRN | `\d{6}-[1-4]\d{6}` | 900115-1234567 |

#### Masking Strategies

| Strategy | Reversible | Use Case | Example |
|----------|-----------|----------|---------|
| Tokenization | Yes (with vault) | Payment processing, cross-system references | `tok_abc123` |
| Format-preserving encryption | Yes (with key) | Legacy system compatibility | `4111-****-****-7890` |
| k-Anonymity | No | Analytics datasets | Generalize age to range (30-40) |
| l-Diversity | No | Analytics with sensitive attributes | Ensure diverse values per equivalence class |
| Differential Privacy | No | Aggregate queries | Add calibrated noise to query results |
| Pseudonymization | Yes (with mapping) | Research datasets | Replace name with consistent pseudonym |
| Redaction | No | Log files, support tickets | `[REDACTED]` |

#### Data Classification Levels

| Level | Label | Examples | Default Masking |
|-------|-------|---------|-----------------|
| L0 | Public | Marketing content, public docs | None |
| L1 | Internal | Employee directory, org charts | Access control only |
| L2 | Confidential | Customer PII, financial data | Tokenize/encrypt |
| L3 | Restricted | Credentials, health data, payment data | Encrypt + audit all access |

### 4.4 Data Minimization

#### Collection Minimization

- Audit every form field: is this data strictly necessary for the stated purpose?
- Default optional fields to not collected (opt-in, not opt-out)
- Implement progressive profiling: collect data gradually as trust builds
- Use purpose-specific consent: separate consent for each processing purpose

#### Storage Minimization (TTL-Based Expiry)

```sql
-- PostgreSQL: automatic TTL-based expiry
CREATE TABLE session_data (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL,
    data JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT now() + INTERVAL '24 hours'
);

-- Automated cleanup job
CREATE OR REPLACE FUNCTION cleanup_expired_data() RETURNS void AS $$
BEGIN
    DELETE FROM session_data WHERE expires_at < now();
    DELETE FROM verification_tokens WHERE expires_at < now();
    DELETE FROM password_reset_tokens WHERE expires_at < now();
END;
$$ LANGUAGE plpgsql;

-- Schedule via pg_cron
SELECT cron.schedule('cleanup-expired', '0 * * * *', 'SELECT cleanup_expired_data()');
```

#### Processing Minimization

- Aggregate instead of processing individual records when possible
- Use statistical sampling for analytics rather than full dataset scans
- Apply data projection: only query the columns actually needed
- Implement view-based access: expose only relevant data subsets to each service

#### Access Minimization

- Need-to-know basis: grant access only when there is a documented business need
- Time-limited access: use just-in-time (JIT) provisioning for elevated access
- Regular access reviews: quarterly review of who has access to what
- Automated access revocation: deprovision on role change or termination
<!-- SECTION:c4-privacy-engineer:END -->
