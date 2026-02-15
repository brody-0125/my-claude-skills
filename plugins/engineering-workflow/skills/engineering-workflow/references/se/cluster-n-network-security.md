# SE Network Security Cluster Reference

> Reference material for agents N-1, N-2, N-3, N-4

## Table of Contents

| Section | Agent | Line Range |
|---------|-------|------------|
| Security Headers | n1-header-hardener | 20-110 |
| WAF & Rate Limiting | n2-waf-rule-designer | 111-200 |
| API Gateway Security | n3-api-gateway-security | 201-280 |
| Input Validation Patterns | n4-input-sanitizer | 281-350 |

---

<!-- SECTION:n1-header-hardener:START -->

## 1. Security Headers

Security headers are the first line of defense enforced by the browser. A missing
or misconfigured header can expose the entire application to client-side attacks.

### 1.1 Content-Security-Policy (CSP)

CSP controls which resources the browser is allowed to load.
A well-crafted policy mitigates XSS, data injection, and clickjacking.

#### Directive Reference

| Directive | Purpose | Recommended Value |
|-----------|---------|-------------------|
| `default-src` | Fallback for all resource types | `'self'` |
| `script-src` | JavaScript sources | `'self' 'nonce-{random}'` or `'strict-dynamic'` |
| `style-src` | CSS sources | `'self' 'unsafe-inline'` (with hash preferred) |
| `img-src` | Image sources | `'self' data: https:` |
| `connect-src` | Fetch/XHR/WebSocket targets | `'self' https://api.example.com` |
| `frame-ancestors` | Controls embedding (replaces X-Frame-Options) | `'none'` or `'self'` |
| `base-uri` | Restricts `<base>` element | `'self'` |
| `form-action` | Restricts form submission targets | `'self'` |
| `object-src` | Plugin content (Flash, Java) | `'none'` |
| `upgrade-insecure-requests` | Auto-upgrade HTTP to HTTPS | (directive present) |

#### Nonce-Based CSP for Inline Scripts

Generate a cryptographic random nonce per request and inject it into both
the CSP header and every `<script>` tag.

```
Content-Security-Policy: default-src 'self'; script-src 'self' 'nonce-4AEemGb0xJptoIGFP3Nd'
```

```html
<script nonce="4AEemGb0xJptoIGFP3Nd">
  // Inline script allowed because nonce matches
</script>
```

#### strict-dynamic

When `'strict-dynamic'` is present, scripts loaded by an already-trusted script
are also trusted, regardless of origin. This simplifies CSP for complex SPAs:

```
Content-Security-Policy: script-src 'strict-dynamic' 'nonce-{random}'; object-src 'none'; base-uri 'self'
```

#### CSP for SPA (React/Vue/Angular)

```
Content-Security-Policy: default-src 'self'; script-src 'self' 'nonce-{random}'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self' https://api.example.com wss://ws.example.com; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; upgrade-insecure-requests
```

#### CSP for Server-Rendered (SSR)

```
Content-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; font-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'
```

#### Report-URI / Report-To

Deploy in report-only mode first to avoid breaking production:

```
Content-Security-Policy-Report-Only: default-src 'self'; report-uri /csp-report; report-to csp-endpoint
```

```json
// Report-To header group definition
Report-To: {"group":"csp-endpoint","max_age":86400,"endpoints":[{"url":"https://report.example.com/csp"}]}
```

### 1.2 CORS Configuration

Cross-Origin Resource Sharing must be configured explicitly. Misconfiguration
is the most common gateway for credential theft.

#### Origin Whitelist (Spring Boot)

```kotlin
@Configuration
class CorsConfig : WebMvcConfigurer {
    override fun addCorsMappings(registry: CorsRegistry) {
        registry.addMapping("/api/**")
            .allowedOrigins("https://app.example.com", "https://admin.example.com")
            .allowedMethods("GET", "POST", "PUT", "DELETE", "OPTIONS")
            .allowedHeaders("Authorization", "Content-Type", "X-Request-ID")
            .exposedHeaders("X-RateLimit-Remaining", "X-RateLimit-Reset")
            .allowCredentials(true)
            .maxAge(3600)  // Preflight cache: 1 hour
    }
}
```

#### Common CORS Misconfigurations

| Misconfiguration | Risk | Fix |
|-----------------|------|-----|
| `Access-Control-Allow-Origin: *` with credentials | Credential theft | Use explicit origin whitelist |
| Reflecting request Origin header without validation | Same as wildcard | Validate against allow-list |
| Missing `Vary: Origin` header | Cache poisoning | Always include `Vary: Origin` |
| Overly broad `allowedMethods` | Unexpected mutations | List only required methods |

### 1.3 HSTS (HTTP Strict Transport Security)

```
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
```

| Parameter | Value | Requirement |
|-----------|-------|-------------|
| `max-age` | 31536000 (1 year minimum) | Required for preload list |
| `includeSubDomains` | present | Required for preload list |
| `preload` | present | Submit to hstspreload.org |

Deployment order: start with `max-age=300`, verify no mixed content, increase
to `max-age=31536000`, then add `preload`.

### 1.4 Other Security Headers

| Header | Value | Purpose |
|--------|-------|---------|
| `X-Content-Type-Options` | `nosniff` | Prevent MIME type sniffing |
| `X-Frame-Options` | `DENY` or `SAMEORIGIN` | Clickjacking prevention (legacy; prefer `frame-ancestors`) |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Control referrer leakage |
| `Permissions-Policy` | `camera=(), microphone=(), geolocation=(), payment=()` | Disable unused browser APIs |
| `Cross-Origin-Opener-Policy` | `same-origin` | Isolate browsing context (Spectre mitigation) |
| `Cross-Origin-Resource-Policy` | `same-origin` | Prevent cross-origin reads |
| `Cross-Origin-Embedder-Policy` | `require-corp` | Enable `SharedArrayBuffer` safely |
| `Cache-Control` | `no-store` (for sensitive pages) | Prevent caching of authenticated content |
| `X-DNS-Prefetch-Control` | `off` | Prevent DNS prefetch information leakage |

<!-- SECTION:n1-header-hardener:END -->
<!-- SECTION:n2-waf-rule-designer:START -->

## 2. WAF & Rate Limiting

### 2.1 AWS WAF Managed Rule Groups

| Rule Group | Protects Against | WCU Cost |
|-----------|------------------|----------|
| `AWSManagedRulesCommonRuleSet` | OWASP Top 10 basics (XSS, path traversal, etc.) | 700 |
| `AWSManagedRulesSQLiRuleSet` | SQL injection patterns | 200 |
| `AWSManagedRulesKnownBadInputsRuleSet` | Log4j, known exploit payloads | 200 |
| `AWSManagedRulesAnonymousIpList` | VPN, Tor, hosting providers | 50 |
| `AWSManagedRulesBotControlRuleSet` | Bot traffic (targeted + common) | 50 |
| `AWSManagedRulesATPRuleSet` | Account takeover (credential stuffing) | 50 |

AWS WAF rule evaluation order: rules are evaluated by priority (lower number first).
Place rate-based rules before managed rules to short-circuit high-volume attacks.

#### Custom Rule Example (Block SQL Injection in Query String)

```json
{
  "Name": "BlockSQLiInQueryString",
  "Priority": 1,
  "Statement": {
    "SqliMatchStatement": {
      "FieldToMatch": { "QueryString": {} },
      "TextTransformations": [
        { "Priority": 0, "Type": "URL_DECODE" },
        { "Priority": 1, "Type": "LOWERCASE" }
      ]
    }
  },
  "Action": { "Block": {} },
  "VisibilityConfig": {
    "SampledRequestsEnabled": true,
    "CloudWatchMetricsEnabled": true,
    "MetricName": "BlockSQLiInQueryString"
  }
}
```

### 2.2 Rate Limiting Strategies

#### Algorithm Comparison

| Algorithm | Pros | Cons | Best For |
|-----------|------|------|----------|
| Fixed Window | Simple, low memory | Burst at window boundary | Basic protection |
| Sliding Window Log | Accurate, no boundary burst | High memory (stores timestamps) | Low-volume APIs |
| Sliding Window Counter | Good accuracy, low memory | Approximation | General purpose |
| Token Bucket | Allows controlled bursts | Slightly more complex | APIs needing burst tolerance |
| Leaky Bucket | Smooth output rate | No burst tolerance | Streaming/rate-sensitive |

#### Configuration Example

```yaml
rate_limits:
  global:
    window: 60s
    max_requests: 1000
    key: ip
    action: throttle
    response_code: 429
    retry_after: 60

  endpoints:
    - path: /api/auth/login
      window: 60s
      max_requests: 5
      key: ip
      action: block
      retry_after: 300
      alert: true

    - path: /api/auth/password-reset
      window: 3600s
      max_requests: 3
      key: ip+email
      action: block
      retry_after: 3600

    - path: /api/search
      window: 60s
      max_requests: 30
      key: user_id
      action: throttle
      degrade_to: cached_results

    - path: /api/**
      window: 60s
      max_requests: 100
      key: user_id
      action: throttle
```

#### 429 Response Best Practice

```http
HTTP/1.1 429 Too Many Requests
Retry-After: 300
X-RateLimit-Limit: 5
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1705312800
Content-Type: application/json

{"error": "rate_limit_exceeded", "message": "Too many requests. Please retry after 300 seconds."}
```

### 2.3 DDoS Mitigation Layers

| Layer | Protection | Service | Automation |
|-------|-----------|---------|------------|
| L3/L4 | Volumetric flood, SYN flood | AWS Shield Standard/Advanced, Cloudflare Spectrum | Always-on |
| L7 | HTTP flood, slowloris | AWS WAF, Cloudflare WAF | Rate-based rules + managed rules |
| Application | Logic abuse, scraping | Custom rate limiting, CAPTCHA | Adaptive (behavior-based) |
| DNS | DNS amplification | Route 53 Shield, Cloudflare DNS | Anycast + rate limiting |

#### Backpressure Pattern (Application Level)

```kotlin
@Component
class BackpressureFilter : WebFilter {
    private val semaphore = Semaphore(500) // max concurrent requests

    override fun filter(exchange: ServerWebExchange, chain: WebFilterChain): Mono<Void> {
        if (!semaphore.tryAcquire()) {
            exchange.response.statusCode = HttpStatus.SERVICE_UNAVAILABLE
            exchange.response.headers.set("Retry-After", "5")
            return exchange.response.setComplete()
        }
        return chain.filter(exchange)
            .doFinally { semaphore.release() }
    }
}
```

<!-- SECTION:n2-waf-rule-designer:END -->
<!-- SECTION:n3-api-gateway-security:START -->

## 3. API Gateway Security

### 3.1 Auth Delegation Patterns

| Pattern | Latency | Use Case | Tradeoff |
|---------|---------|----------|----------|
| JWT validation at gateway | Low (no upstream call) | Stateless APIs | Revocation delay until token expiry |
| OAuth token introspection | Medium (call to IdP) | Fine-grained revocation | Extra network hop |
| API key lookup | Low (cache-backed) | Third-party integrations | Limited security (no user context) |
| Mutual TLS (mTLS) | Low (TLS handshake) | Service-to-service | Certificate management overhead |

#### JWT Validation at Gateway (Kong Example)

```yaml
plugins:
  - name: jwt
    config:
      uri_param_names: []
      claims_to_verify:
        - exp
        - iss
      key_claim_name: iss
      maximum_expiration: 3600
      header_names:
        - Authorization
```

#### mTLS Configuration (Istio)

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT
---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: order-service-policy
  namespace: production
spec:
  selector:
    matchLabels:
      app: order-service
  rules:
    - from:
        - source:
            principals: ["cluster.local/ns/production/sa/api-gateway"]
      to:
        - operation:
            methods: ["GET", "POST"]
            paths: ["/api/orders/*"]
```

### 3.2 Request Validation

#### OpenAPI Schema Validation

Validate every incoming request against the published OpenAPI spec
at the gateway. Reject requests that do not conform before they reach
upstream services.

```yaml
# Kong Plugin Configuration
plugins:
  - name: request-validator
    config:
      body_schema: |
        {
          "type": "object",
          "required": ["name", "email"],
          "properties": {
            "name": {"type": "string", "maxLength": 200},
            "email": {"type": "string", "format": "email"}
          },
          "additionalProperties": false
        }
      allowed_content_types:
        - application/json
      verbose_response: false
```

#### Payload Size & Content-Type Enforcement

| Parameter | Recommended Default | Sensitive Endpoints |
|-----------|-------------------|---------------------|
| Max body size | 1 MB | 10 KB (login, API key endpoints) |
| Allowed content types | `application/json` | Explicit whitelist only |
| Max header size | 8 KB | 4 KB |
| Max URL length | 2048 characters | 512 characters |
| Max query parameters | 20 | 5 |

#### Request ID Injection

Inject a unique request ID at the gateway for end-to-end tracing:

```
X-Request-ID: 01HQXG5K3N7MJRS0P4VBCXW8KN  (ULID format)
X-Correlation-ID: session-level-id          (if provided by client)
```

### 3.3 Throttling Architecture

#### Per-Client Quotas

```yaml
quota_policies:
  free_tier:
    daily_limit: 1000
    burst_limit: 10     # requests per second
    monthly_limit: 25000

  standard_tier:
    daily_limit: 50000
    burst_limit: 100
    monthly_limit: 1000000

  enterprise_tier:
    daily_limit: unlimited
    burst_limit: 1000
    monthly_limit: unlimited
```

#### Quota Response Headers

```http
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 742
X-RateLimit-Reset: 1705363200
X-Quota-Limit: 25000
X-Quota-Remaining: 18320
X-Quota-Reset: 1706745600
```

<!-- SECTION:n3-api-gateway-security:END -->
<!-- SECTION:n4-input-sanitizer:START -->

## 4. Input Validation Patterns

### 4.1 SQL Injection Prevention

#### Parameterized Queries (JDBC PreparedStatement)

```java
// SAFE: parameterized query
String sql = "SELECT * FROM users WHERE email = ? AND status = ?";
PreparedStatement stmt = connection.prepareStatement(sql);
stmt.setString(1, email);
stmt.setString(2, status);
ResultSet rs = stmt.executeQuery();
```

#### JPA Named Parameters

```kotlin
@Query("SELECT u FROM User u WHERE u.email = :email AND u.org = :orgId")
fun findByEmailAndOrg(
    @Param("email") email: String,
    @Param("orgId") orgId: Long
): User?
```

#### Spring Data JPA Specification (Dynamic Queries)

```kotlin
fun buildSpec(filter: UserFilter): Specification<User> {
    return Specification.where<User> { root, _, cb ->
        val predicates = mutableListOf<Predicate>()
        filter.name?.let { predicates.add(cb.like(cb.lower(root.get("name")), "%${it.lowercase()}%")) }
        filter.status?.let { predicates.add(cb.equal(root.get<String>("status"), it)) }
        cb.and(*predicates.toTypedArray())
    }
}
```

#### Validation Regex for Common Inputs

| Input | Pattern | Max Length |
|-------|---------|-----------|
| Email | `^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$` | 254 |
| Username | `^[a-zA-Z0-9_\-]{3,30}$` | 30 |
| UUID | `^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$` | 36 |
| Phone (E.164) | `^\+[1-9]\d{1,14}$` | 15 |
| Slug | `^[a-z0-9]+(?:-[a-z0-9]+)*$` | 100 |
| Integer ID | `^\d{1,19}$` | 19 |

### 4.2 XSS Prevention

#### Context-Aware Output Encoding

| Context | Encoding | Example |
|---------|----------|---------|
| HTML body | HTML entity encoding | `<` -> `&lt;` |
| HTML attribute | Attribute encoding (quote all values) | `"` -> `&quot;` |
| JavaScript string | JS hex encoding | `'` -> `\x27` |
| URL parameter | Percent encoding | `<` -> `%3C` |
| CSS value | CSS hex encoding | `(` -> `\28` |

#### Spring HtmlUtils

```kotlin
import org.springframework.web.util.HtmlUtils

val safe = HtmlUtils.htmlEscape(userInput)         // HTML context
val safeJs = JavaScriptUtils.javaScriptEscape(userInput)  // JS context
```

#### DOMPurify (Client-Side)

```javascript
import DOMPurify from 'dompurify';

const clean = DOMPurify.sanitize(dirtyHtml, {
  ALLOWED_TAGS: ['b', 'i', 'em', 'strong', 'a', 'p', 'br'],
  ALLOWED_ATTR: ['href', 'title'],
  ALLOW_DATA_ATTR: false,
  ADD_ATTR: ['target'],
  FORBID_TAGS: ['script', 'style', 'iframe', 'object', 'embed'],
});
```

### 4.3 Path Traversal Prevention

```kotlin
fun resolveSecurePath(baseDir: Path, userInput: String): Path {
    val resolved = baseDir.resolve(userInput).normalize()
    require(resolved.startsWith(baseDir)) {
        "Path traversal attempt detected: $userInput"
    }
    return resolved
}

// Usage
val uploadDir = Path.of("/var/app/uploads")
val filePath = resolveSecurePath(uploadDir, request.filename)
```

#### Checklist

- Canonicalize the path using `Path.normalize()` before comparison
- Validate that the resolved path starts with the allowed base directory
- Reject filenames containing `..`, `%2e%2e`, or null bytes (`%00`)
- Use an allow-list of file extensions when applicable
- Never construct paths via string concatenation with user input

### 4.4 File Upload Security

| Control | Implementation | Purpose |
|---------|---------------|---------|
| Extension whitelist | `.jpg`, `.png`, `.pdf`, `.docx` | Block executable uploads |
| Magic byte validation | Check file header bytes, not just extension | Prevent extension spoofing |
| Content-Type validation | Validate against magic bytes, not client-provided header | Prevent MIME mismatch |
| Size limit | 10 MB default, configurable per endpoint | Prevent resource exhaustion |
| Virus scanning | ClamAV via clamdscan or REST API | Detect known malware |
| Isolated storage | S3 bucket with `x-amz-server-side-encryption` | No local file execution risk |
| Random filename | UUID-based rename on upload | Prevent name collision and path traversal |
| No-execute policy | Remove execute permissions; serve via CDN with `Content-Disposition: attachment` | Prevent server-side execution |

#### Secure Upload Flow

```kotlin
@PostMapping("/upload")
fun upload(@RequestParam file: MultipartFile): ResponseEntity<UploadResponse> {
    // 1. Validate extension
    val ext = file.originalFilename?.substringAfterLast('.', "")?.lowercase()
    require(ext in ALLOWED_EXTENSIONS) { "File type not allowed: $ext" }

    // 2. Validate size
    require(file.size <= MAX_FILE_SIZE) { "File too large: ${file.size}" }

    // 3. Validate magic bytes
    val detectedType = Tika().detect(file.inputStream)
    require(detectedType in ALLOWED_MIME_TYPES) { "Content mismatch: $detectedType" }

    // 4. Generate random filename
    val storageName = "${UUID.randomUUID()}.$ext"

    // 5. Upload to isolated storage
    s3Client.putObject(PutObjectRequest.builder()
        .bucket(UPLOAD_BUCKET)
        .key("uploads/$storageName")
        .serverSideEncryption(ServerSideEncryption.AES256)
        .contentDisposition("attachment")
        .build(), RequestBody.fromInputStream(file.inputStream, file.size))

    // 6. Trigger async virus scan
    virusScanService.scanAsync(UPLOAD_BUCKET, "uploads/$storageName")

    return ResponseEntity.ok(UploadResponse(storageName))
}

companion object {
    val ALLOWED_EXTENSIONS = setOf("jpg", "jpeg", "png", "gif", "pdf", "docx")
    val ALLOWED_MIME_TYPES = setOf(
        "image/jpeg", "image/png", "image/gif",
        "application/pdf",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    )
    const val MAX_FILE_SIZE = 10 * 1024 * 1024L  // 10 MB
}
```
<!-- SECTION:n4-input-sanitizer:END -->
