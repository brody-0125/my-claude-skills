# SE Authentication Cluster Reference

> Reference material for agents A-1, A-2, A-3, A-4

## Table of Contents

| Section | Agent | Line Range |
|---------|-------|------------|
| OAuth2/OIDC/SAML Flow Patterns | a1-authn-flow-designer | 20-120 |
| Token Lifecycle Patterns | a2-token-strategist | 121-220 |
| Session Management Patterns | a3-session-architect | 221-310 |
| Credential Storage Patterns | a4-credential-manager | 311-400 |

---

<!-- SECTION:a1-authn-flow-designer:START -->
## 1. OAuth2/OIDC/SAML Flow Patterns

### OAuth2 Authorization Code + PKCE (SPA/Mobile)

PKCE (Proof Key for Code Exchange, RFC 7636) eliminates the need for a client secret
in public clients. The flow proceeds as follows:

```
Client                          Authorization Server          Resource Server
  |                                     |                          |
  |  1. Generate code_verifier          |                          |
  |     (43-128 chars, [A-Za-z0-9-._~]) |                          |
  |  2. code_challenge =               |                          |
  |     BASE64URL(SHA256(code_verifier))|                          |
  |                                     |                          |
  |--3. /authorize?                     |                          |
  |     response_type=code              |                          |
  |     &client_id=...                  |                          |
  |     &redirect_uri=...              |                          |
  |     &scope=openid profile           |                          |
  |     &state=<random>                 |                          |
  |     &code_challenge=<challenge>     |                          |
  |     &code_challenge_method=S256 --->|                          |
  |                                     |                          |
  |<--4. redirect to redirect_uri ------|                          |
  |     ?code=<auth_code>&state=<state> |                          |
  |                                     |                          |
  |--5. POST /token                     |                          |
  |     grant_type=authorization_code   |                          |
  |     &code=<auth_code>               |                          |
  |     &redirect_uri=...              |                          |
  |     &client_id=...                  |                          |
  |     &code_verifier=<verifier> ----->|                          |
  |                                     |                          |
  |<--6. { access_token, refresh_token, |                          |
  |        id_token, expires_in } ------|                          |
  |                                     |                          |
  |--7. GET /resource -------------------------------->|           |
  |     Authorization: Bearer <access_token>           |           |
  |<--8. { protected data } <--------------------------|           |
```

**code_verifier generation (Node.js):**

```javascript
const crypto = require('crypto');

function generateCodeVerifier() {
  // 32 bytes = 43 base64url characters
  return crypto.randomBytes(32)
    .toString('base64url');
}

function generateCodeChallenge(verifier) {
  return crypto.createHash('sha256')
    .update(verifier)
    .digest('base64url');
}

const verifier = generateCodeVerifier();
const challenge = generateCodeChallenge(verifier);
```

**Security considerations for public clients:**
- NEVER use `code_challenge_method=plain` in production; always use `S256`
- Store `code_verifier` in `sessionStorage` (cleared on tab close), not `localStorage`
- Validate `state` parameter to prevent CSRF attacks
- Use short-lived authorization codes (max 10 minutes, single-use)
- Enforce exact `redirect_uri` matching (no wildcards)

### OIDC (OpenID Connect)

OIDC extends OAuth2 with an identity layer. The key addition is the **ID Token**.

**ID Token vs Access Token distinction:**

| Aspect | ID Token | Access Token |
|--------|----------|--------------|
| Purpose | Authentication proof | Resource authorization |
| Audience | Client application | Resource server |
| Format | Always JWT | JWT or opaque |
| Lifetime | Short (5-15 min) | Short-medium (15-60 min) |
| Contains | User identity claims | Scopes/permissions |
| Validation | Client validates | Resource server validates |

**Standard OIDC claims:**

```json
{
  "iss": "https://auth.example.com",
  "sub": "user-uuid-12345",
  "aud": "client-app-id",
  "exp": 1700000000,
  "iat": 1699999000,
  "auth_time": 1699998000,
  "nonce": "random-nonce-value",
  "email": "user@example.com",
  "email_verified": true,
  "name": "Jane Doe",
  "preferred_username": "janedoe",
  "locale": "en-US",
  "zoneinfo": "America/New_York"
}
```

**Discovery document (`.well-known/openid-configuration`):**

```json
{
  "issuer": "https://auth.example.com",
  "authorization_endpoint": "https://auth.example.com/authorize",
  "token_endpoint": "https://auth.example.com/token",
  "userinfo_endpoint": "https://auth.example.com/userinfo",
  "jwks_uri": "https://auth.example.com/.well-known/jwks.json",
  "scopes_supported": ["openid", "profile", "email", "address", "phone"],
  "response_types_supported": ["code", "id_token", "token id_token"],
  "id_token_signing_alg_values_supported": ["RS256", "ES256"],
  "subject_types_supported": ["public", "pairwise"]
}
```

**UserInfo endpoint:** Used when ID token claims are insufficient. Requires a valid access token with `openid` scope. Returns the same claims as the ID token plus any additional requested scopes.

### SAML 2.0 (Enterprise B2B)

**SP-initiated flow (most common):**

```
User          Service Provider (SP)        Identity Provider (IdP)
 |                   |                            |
 | 1. Access resource|                            |
 |------------------>|                            |
 |                   |                            |
 |                   | 2. Generate AuthnRequest   |
 |                   |    (signed XML)             |
 |<--3. Redirect ----|                            |
 |     with SAMLRequest (Base64-encoded)          |
 |----------------------------------------------->|
 |                   |                            |
 |                   |     4. Authenticate user    |
 |<--- Login page --------------------------------|
 |--- Credentials -------------------------------->|
 |                   |                            |
 |<--5. POST SAMLResponse (signed assertion) -----|
 |     to SP's ACS URL                            |
 |------------------>|                            |
 |                   | 6. Validate assertion       |
 |                   |    - XML signature          |
 |                   |    - Conditions (time, aud) |
 |                   |    - Extract attributes     |
 |<--7. Grant access-|                            |
```

**IdP-initiated flow:** The IdP sends an unsolicited SAML Response directly to the SP without a prior AuthnRequest. Less secure (no `InResponseTo` validation), but required by some enterprise IdPs.

**Assertion structure (critical elements):**

```xml
<saml:Assertion Version="2.0" IssueInstant="2024-01-15T10:30:00Z">
  <saml:Issuer>https://idp.enterprise.com</saml:Issuer>
  <ds:Signature>
    <!-- XML Signature (enveloped, RSA-SHA256) -->
  </ds:Signature>
  <saml:Subject>
    <saml:NameID Format="urn:oasis:names:tc:SAML:2.0:nameid-format:emailAddress">
      user@enterprise.com
    </saml:NameID>
    <saml:SubjectConfirmation Method="urn:oasis:names:tc:SAML:2.0:cm:bearer">
      <saml:SubjectConfirmationData
        InResponseTo="_request_id"
        Recipient="https://sp.example.com/saml/acs"
        NotOnOrAfter="2024-01-15T10:35:00Z"/>
    </saml:SubjectConfirmation>
  </saml:Subject>
  <saml:Conditions NotBefore="2024-01-15T10:29:30Z"
                   NotOnOrAfter="2024-01-15T10:35:00Z">
    <saml:AudienceRestriction>
      <saml:Audience>https://sp.example.com</saml:Audience>
    </saml:AudienceRestriction>
  </saml:Conditions>
  <saml:AuthnStatement AuthnInstant="2024-01-15T10:30:00Z">
    <saml:AuthnContext>
      <saml:AuthnContextClassRef>
        urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport
      </saml:AuthnContextClassRef>
    </saml:AuthnContext>
  </saml:AuthnStatement>
  <saml:AttributeStatement>
    <saml:Attribute Name="email">
      <saml:AttributeValue>user@enterprise.com</saml:AttributeValue>
    </saml:Attribute>
    <saml:Attribute Name="groups">
      <saml:AttributeValue>engineering</saml:AttributeValue>
      <saml:AttributeValue>admin</saml:AttributeValue>
    </saml:Attribute>
  </saml:AttributeStatement>
</saml:Assertion>
```

**XML Signature validation checklist:**
1. Verify the signature covers the entire `<Assertion>` element (not just part of it)
2. Validate the signing certificate against the trusted IdP metadata certificate
3. Check for XML Signature Wrapping (XSW) attacks -- ensure the signed node is the one being processed
4. Reject assertions with `<ds:Transform>` that could alter content before signing
5. Validate `NotBefore` / `NotOnOrAfter` conditions with clock skew tolerance (max 30 seconds)

### Protocol Decision Matrix

| Factor | OAuth2+PKCE | OIDC | SAML 2.0 | Custom Token |
|--------|-------------|------|----------|--------------|
| Best for | SPA, Mobile | Web apps needing identity | Enterprise B2B SSO | Internal microservices |
| Token format | Opaque/JWT | JWT (ID token) | XML assertion | Custom JWT |
| Federation | Limited | Good | Excellent | None |
| Mobile support | Excellent | Good | Poor | Varies |
| Complexity | Medium | Medium | High | Low |
| Logout support | Token revocation | RP-Initiated, Back-channel | SLO (Global logout) | Manual invalidation |
| Standards body | IETF (RFC 6749) | OpenID Foundation | OASIS | N/A |
| Payload size | Small (<1KB) | Medium (1-3KB) | Large (5-50KB) | Varies |
<!-- SECTION:a1-authn-flow-designer:END -->

---

<!-- SECTION:a2-token-strategist:START -->
## 2. Token Lifecycle Patterns

### JWT Claims Structure

**Standard (registered) claims (RFC 7519):**

| Claim | Name | Description | Required |
|-------|------|-------------|----------|
| `iss` | Issuer | Token issuer identifier (URL) | Yes |
| `sub` | Subject | Principal the token represents | Yes |
| `aud` | Audience | Intended recipient(s) | Yes |
| `exp` | Expiration | Unix timestamp after which token is invalid | Yes |
| `iat` | Issued At | Unix timestamp when token was issued | Recommended |
| `nbf` | Not Before | Unix timestamp before which token is invalid | Optional |
| `jti` | JWT ID | Unique identifier for token (for revocation) | For refresh tokens |

**Custom claims best practices:**
- Namespace custom claims to avoid collision: `https://example.com/claims/role`
- Keep claims minimal -- JWT is transmitted with every request
- Never include sensitive data (passwords, SSNs, credit card numbers) in claims
- Use short claim names in high-throughput systems: `rol` instead of `role`
- Total JWT size should stay under 4KB (cookie limit, header size limits)

**Claim validation checklist (resource server):**

```python
def validate_jwt(token: str, config: JWTConfig) -> Claims:
    # 1. Decode header (without verification) to get 'kid' and 'alg'
    header = jwt.get_unverified_header(token)
    assert header['alg'] in ['RS256', 'ES256'], "Reject none/HS256 with RSA key"

    # 2. Fetch signing key from JWKS endpoint (cache with TTL)
    signing_key = get_signing_key(header['kid'], config.jwks_uri)

    # 3. Verify signature and decode claims
    claims = jwt.decode(
        token,
        signing_key,
        algorithms=['RS256', 'ES256'],
        audience=config.expected_audience,
        issuer=config.expected_issuer,
    )

    # 4. Additional validations
    assert claims['exp'] > time.time(), "Token expired"
    assert claims.get('nbf', 0) <= time.time(), "Token not yet valid"
    assert claims['iss'] == config.expected_issuer, "Invalid issuer"
    assert config.expected_audience in claims['aud'], "Invalid audience"

    return claims
```

### Token Strategy Patterns

#### Short-lived Access + Long-lived Refresh

```
Access Token:
  - TTL: 15 minutes (configurable: 5-60 min depending on risk)
  - Format: JWT (stateless validation at resource server)
  - Storage: In-memory (SPA) or httpOnly cookie (server-rendered)
  - Validation: Signature + claims check only (no DB lookup)

Refresh Token:
  - TTL: 7-30 days (shorter for high-risk apps)
  - Format: Opaque random string (256-bit minimum entropy)
  - Storage: Server-side (Redis/DB) + httpOnly Secure cookie on client
  - Validation: DB lookup required (enables immediate revocation)
  - Rotation: Issue new refresh token with each use
```

**Refresh token rotation (replay detection):**

```javascript
async function refreshTokens(currentRefreshToken) {
  const stored = await redis.get(`rt:${hash(currentRefreshToken)}`);

  if (!stored) {
    // Token not found -- could be replay attack
    // Revoke entire token family
    await revokeTokenFamily(stored?.familyId);
    throw new SecurityError('Refresh token reuse detected');
  }

  if (stored.used) {
    // Already used -- definite replay attack
    await revokeTokenFamily(stored.familyId);
    await alertSecurityTeam(stored.userId, 'token_replay');
    throw new SecurityError('Refresh token replay detected');
  }

  // Mark current token as used
  await redis.set(`rt:${hash(currentRefreshToken)}`, { ...stored, used: true });

  // Generate new token pair
  const newAccessToken = generateAccessToken(stored.userId, stored.scopes);
  const newRefreshToken = generateRefreshToken();

  // Store new refresh token in same family
  await redis.set(`rt:${hash(newRefreshToken)}`, {
    userId: stored.userId,
    familyId: stored.familyId,
    scopes: stored.scopes,
    used: false,
    createdAt: Date.now()
  }, 'EX', 30 * 86400); // 30-day TTL

  return { accessToken: newAccessToken, refreshToken: newRefreshToken };
}
```

#### Token Binding -- DPoP (Demonstration of Proof-of-Possession)

DPoP (RFC 9449) binds tokens to a specific client key pair, preventing stolen tokens from being used by a different client.

```
Client generates ephemeral key pair (ES256):

DPoP Proof JWT Header:
{
  "typ": "dpop+jwt",
  "alg": "ES256",
  "jwk": { /* public key */ }
}

DPoP Proof JWT Payload:
{
  "jti": "unique-id",
  "htm": "POST",
  "htu": "https://auth.example.com/token",
  "iat": 1699999000,
  "ath": "base64url(sha256(access_token))"  // only for resource requests
}

Token request includes: DPoP: <dpop_proof_jwt>
Access token includes: "cnf": { "jkt": "thumbprint-of-dpop-key" }
Resource server verifies: DPoP proof signature matches token's jkt thumbprint
```

### Storage Security Matrix

| Storage Location | XSS Risk | CSRF Risk | Tab Persistence | Best For |
|------------------|----------|-----------|-----------------|----------|
| httpOnly cookie | Protected | Vulnerable (need CSRF token) | Yes | Server-rendered apps |
| localStorage | Vulnerable | Protected | Yes (permanent) | NOT recommended for tokens |
| sessionStorage | Vulnerable | Protected | No (tab only) | Short-lived data, not tokens |
| In-memory (closure) | Protected | Protected | No (lost on refresh) | SPA with silent refresh |
| httpOnly + SameSite=Strict | Protected | Protected | Yes | Best overall for web |
| Service Worker cache | Protected | Protected | Yes | Progressive web apps |

### Revocation Patterns

**Token blacklist (Redis SET):**

```python
# On revocation event
async def revoke_token(jti: str, exp: int):
    ttl = exp - int(time.time())
    if ttl > 0:
        await redis.setex(f"blacklist:{jti}", ttl, "1")

# On token validation
async def is_token_revoked(jti: str) -> bool:
    return await redis.exists(f"blacklist:{jti}")
```

**Event-driven revocation (for microservices):**

```yaml
# Kafka topic: token-revocation-events
event:
  type: TOKEN_REVOKED
  payload:
    user_id: "user-123"
    revoke_all_before: "2024-01-15T10:30:00Z"  # iat-based revocation
    reason: "password_changed"
    # Each service maintains a local cache of revocation events
```

**JTI tracking for high-security scenarios:** Maintain a set of valid JTIs instead of a blacklist. More expensive but guarantees no revoked token can be used. Suitable when token volume is low and security requirements are extreme.
<!-- SECTION:a2-token-strategist:END -->

---

<!-- SECTION:a3-session-architect:START -->
## 3. Session Management Patterns

### Server-side vs Stateless Comparison

| Aspect | Server-side (Redis) | Stateless (JWT) | Hybrid |
|--------|---------------------|-----------------|--------|
| Scalability | Requires shared store | Excellent | Good |
| Revocation | Immediate | Requires blacklist | Immediate for sensitive ops |
| Data size | Unlimited | ~4KB header limit | Flexible |
| Clock skew | Not affected | Critical (use <=30s tolerance) | Partial |
| Performance | Network roundtrip to store | CPU for signature verify | Varies |
| Consistency | Strong (single source) | Eventually consistent | Tunable |
| Operational | Redis HA required | Stateless, simple deploy | Moderate |

**Hybrid approach (recommended for most applications):**

```python
# Short-lived JWT for authentication (15 min)
# Server-side session for mutable state (permissions, preferences)
# Redis for session store with automatic expiry

class HybridSession:
    def __init__(self, redis_client):
        self.redis = redis_client

    async def create_session(self, user_id: str, claims: dict) -> dict:
        session_id = secrets.token_urlsafe(32)
        access_token = create_jwt(user_id, claims, ttl=900)  # 15 min

        await self.redis.hset(f"session:{session_id}", mapping={
            "user_id": user_id,
            "permissions": json.dumps(claims.get("permissions", [])),
            "mfa_verified": "false",
            "created_at": str(int(time.time())),
            "last_activity": str(int(time.time()))
        })
        await self.redis.expire(f"session:{session_id}", 43200)  # 12h absolute

        return {"access_token": access_token, "session_id": session_id}
```

### MFA Integration Flows

**TOTP setup flow:**

```
1. Server generates secret: base32encode(random(20 bytes))
2. Server creates provisioning URI:
   otpauth://totp/Example:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example&digits=6&period=30
3. Client displays QR code of provisioning URI
4. User scans with authenticator app (Google Authenticator, Authy, 1Password)
5. User enters current TOTP code to verify setup
6. Server stores: { user_id, totp_secret (encrypted), backup_codes: [8 codes], enabled_at }
```

**TOTP verification (with clock drift tolerance):**

```python
import pyotp

def verify_totp(secret: str, code: str, window: int = 1) -> bool:
    """Verify TOTP with +/- 1 time step tolerance (30s each direction)."""
    totp = pyotp.TOTP(secret)
    return totp.verify(code, valid_window=window)
```

**WebAuthn challenge/response (FIDO2):**

```javascript
// Registration (navigator.credentials.create)
const credential = await navigator.credentials.create({
  publicKey: {
    challenge: new Uint8Array(serverChallenge),       // 32+ random bytes from server
    rp: { name: "Example Corp", id: "example.com" },  // Relying Party
    user: {
      id: new Uint8Array(userId),
      name: "user@example.com",
      displayName: "Jane Doe"
    },
    pubKeyCredParams: [
      { alg: -7, type: "public-key" },   // ES256 (preferred)
      { alg: -257, type: "public-key" }  // RS256 (fallback)
    ],
    authenticatorSelection: {
      authenticatorAttachment: "platform",    // built-in (Touch ID, Windows Hello)
      residentKey: "preferred",               // discoverable credential (passkey)
      userVerification: "required"            // biometric/PIN required
    },
    timeout: 60000,
    attestation: "none"  // "direct" if attestation verification needed
  }
});
// Send credential.response (attestationObject + clientDataJSON) to server
```

**MFA step-up authentication trigger conditions:**
- Accessing sensitive resources (financial data, PII, admin panels)
- Changing security settings (password, email, MFA devices)
- First login from a new device or geographic location
- Elevated privilege requests (sudo-style)
- After session idle period exceeds threshold (e.g., 15 minutes)

### SSO Federation Patterns

**IdP Discovery (Home Realm Discovery):**
- Email domain mapping: `@acme.com` -> `https://idp.acme.com`
- Vanity URL: `https://app.example.com/login/acme`
- Cookie-based: remember last used IdP in a domain cookie
- WAYF (Where Are You From) page: dropdown of configured IdPs

**Session synchronization across services:**

```
                    SSO Session (IdP)
                    TTL: 8 hours
                   /        |         \
            Service A    Service B    Service C
            Session      Session      Session
            TTL: 1h      TTL: 30m    TTL: 2h
```

Each service maintains its own session linked to the SSO session. When a service session expires, it silently redirects to the IdP; if the SSO session is still valid, the user gets a new service session without re-authentication (silent login).

**Global logout (front-channel vs back-channel):**

| Method | Mechanism | Reliability | User Experience |
|--------|-----------|-------------|-----------------|
| Front-channel | Hidden iframes to each SP logout URL | Low (blocked by browsers) | Synchronous |
| Back-channel | Server-to-server HTTP POST | High | Asynchronous |
| OIDC RP-Initiated | Redirect to IdP end_session_endpoint | Medium | Redirect chain |

### Session Security Controls

**Session fixation prevention:**

```python
@app.post("/login")
async def login(credentials: Credentials, request: Request, response: Response):
    user = await authenticate(credentials)
    if user:
        # Regenerate session ID after successful authentication
        old_session = request.session
        request.session.regenerate()  # New session ID, copy data
        # Invalidate old session ID
        await session_store.delete(old_session.id)
```

**Secure cookie attributes:**

```
Set-Cookie: session_id=<value>;
  Secure;                    # HTTPS only
  HttpOnly;                  # No JavaScript access
  SameSite=Lax;              # CSRF protection (Strict for sensitive apps)
  Domain=.example.com;       # Scoped to domain
  Path=/;                    # Available to all paths
  Max-Age=43200;             # 12 hours absolute timeout
  __Host- prefix             # Requires Secure, no Domain, Path=/
```

**Concurrent session limits:** Track active sessions per user in Redis. On new login, either reject (strict) or terminate oldest session (FIFO). Alert user when sessions are terminated.
<!-- SECTION:a3-session-architect:END -->

---

<!-- SECTION:a4-credential-manager:START -->
## 4. Credential Storage Patterns

### Hashing Algorithm Comparison

| Algorithm | Memory Cost | Time Cost | Parallelism | GPU Resistance | Status |
|-----------|-------------|-----------|-------------|----------------|--------|
| bcrypt | 4KB fixed | ~100ms | None | Moderate | Legacy, still acceptable |
| scrypt | Configurable | Configurable | Configurable | Good | Good for custom needs |
| Argon2i | Configurable | Configurable | Configurable | Good (data-independent) | Side-channel resistant |
| Argon2d | Configurable | Configurable | Configurable | Excellent (data-dependent) | Fastest, less side-channel safe |
| Argon2id | Configurable | Configurable | Configurable | Excellent (hybrid) | OWASP recommended |
| PBKDF2 | None | Iteration count | None | Poor | FIPS compliant only |

### Argon2id Recommended Parameters

```
# OWASP recommendations (2024)
Minimum:
  memory     = 19456 KB (19 MB)
  iterations = 2
  parallelism = 1
  hash_length = 32 bytes
  salt_length = 16 bytes

Recommended:
  memory     = 65536 KB (64 MB)
  iterations = 3
  parallelism = 4
  hash_length = 32 bytes
  salt_length = 16 bytes

High-security (authentication servers with dedicated resources):
  memory     = 262144 KB (256 MB)
  iterations = 4
  parallelism = 8
  hash_length = 64 bytes
  salt_length = 32 bytes
```

**Implementation (Python):**

```python
import argon2

hasher = argon2.PasswordHasher(
    time_cost=3,          # iterations
    memory_cost=65536,    # 64 MB
    parallelism=4,
    hash_len=32,
    salt_len=16,
    type=argon2.Type.ID   # Argon2id
)

# Hash
hashed = hasher.hash("user_password")
# Result: $argon2id$v=19$m=65536,t=3,p=4$<salt>$<hash>

# Verify
try:
    hasher.verify(hashed, "user_password")
    # Check if rehash needed (params upgraded)
    if hasher.check_needs_rehash(hashed):
        new_hash = hasher.hash("user_password")
        update_stored_hash(user_id, new_hash)
except argon2.exceptions.VerifyMismatchError:
    raise AuthenticationError("Invalid credentials")
```

### WebAuthn/Passkey Flow

**Registration ceremony (detailed):**

```
1. Server: Generate challenge (32+ random bytes), store with user session
2. Client: Call navigator.credentials.create(publicKeyOptions)
3. Authenticator:
   a. Verify RP ID matches current origin
   b. User verification (biometric/PIN)
   c. Generate new key pair (ES256)
   d. Create attestation object:
      - authData: rpIdHash (32B) + flags (1B) + signCount (4B)
                  + attestedCredentialData (AAGUID + credId + pubKey)
      - attStmt: attestation signature (optional, "none" for privacy)
4. Client: Return AuthenticatorAttestationResponse to server
5. Server:
   a. Verify clientDataJSON.challenge matches stored challenge
   b. Verify clientDataJSON.origin matches expected origin
   c. Verify rpIdHash in authData matches SHA-256(rp.id)
   d. Verify UV flag is set (user verification performed)
   e. Extract and store: credentialId, publicKey, signCount, transports
```

**Authentication ceremony:**

```
1. Server: Generate challenge, retrieve user's registered credentials
2. Client: Call navigator.credentials.get({
     publicKey: {
       challenge: serverChallenge,
       rpId: "example.com",
       allowCredentials: [{ id: credId, type: "public-key", transports: ["internal"] }],
       userVerification: "required"
     }
   })
3. Authenticator: Sign challenge with stored private key
4. Server:
   a. Verify clientDataJSON.challenge and origin
   b. Verify authenticatorData.rpIdHash
   c. Verify signature using stored public key
   d. Verify signCount > stored signCount (detect cloned authenticator)
   e. Update stored signCount
```

**Authenticator types:**

| Type | Example | Attachment | Passkey Support |
|------|---------|------------|-----------------|
| Platform | Touch ID, Face ID, Windows Hello | Built-in | Yes (synced via iCloud/Google) |
| Roaming | YubiKey, Titan Key | USB/NFC/BLE | Yes (device-bound) |

### Credential Rotation Policy

**NIST 800-63B guidance (current):**
- Do NOT enforce periodic password rotation (increases weak password selection)
- DO force rotation on evidence of compromise
- DO check passwords against known-breached lists (e.g., HaveIBeenPwned API)
- DO enforce minimum length (8 characters absolute minimum, 15+ recommended)
- DO allow maximum length of at least 64 characters
- DO support all printable ASCII and Unicode characters

**Breach-triggered rotation flow:**

```python
async def check_credential_breach(user_id: str):
    user = await get_user(user_id)

    # Check against HaveIBeenPwned k-anonymity API
    sha1_hash = hashlib.sha1(user.password_plaintext_never_store).hexdigest().upper()
    prefix, suffix = sha1_hash[:5], sha1_hash[5:]

    response = await httpx.get(f"https://api.pwnedpasswords.com/range/{prefix}")
    breached = any(line.startswith(suffix) for line in response.text.splitlines())

    if breached:
        await force_password_reset(user_id, reason="credential_breach_detected")
        await revoke_all_sessions(user_id)
        await notify_user(user_id, "Your password was found in a data breach")
```

**Progressive security upgrade (password to passkey migration):**

```
Phase 1: Offer passkey registration after successful password login
Phase 2: Prompt passkey registration on security settings page
Phase 3: Show passkey-first login UI (password as fallback)
Phase 4: Allow users to remove password entirely (passkey-only)
         (Only after at least 2 passkeys registered for recovery)
```

**Credential stuffing detection signals:**
- Multiple failed logins from same IP with different usernames
- Login attempts with known breached username/password pairs
- Abnormal geographic distribution of login attempts
- Automated request patterns (consistent timing, missing browser fingerprint)
- Response: progressive delays, CAPTCHA, IP-based rate limiting, account lockout
<!-- SECTION:a4-credential-manager:END -->
