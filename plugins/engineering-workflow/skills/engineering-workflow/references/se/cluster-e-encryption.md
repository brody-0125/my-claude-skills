# SE Encryption Cluster Reference

> Reference material for agents E-1, E-2, E-3, E-4

## Table of Contents

| Section | Agent | Line Range |
|---------|-------|------------|
| Encryption Algorithms & Strategy | e1-encryption-advisor | 20-130 |
| Key Management Lifecycle | e2-key-lifecycle-planner | 131-230 |
| TLS/mTLS Configuration | e3-tls-configurator | 231-320 |
| Secret Management Patterns | e4-secret-manager | 321-400 |

---

<!-- SECTION:e1-encryption-advisor:START -->
## 1. Encryption Algorithms & Strategy

### Symmetric Algorithms

#### AES-256-GCM (Authenticated Encryption with Associated Data)

AES-GCM provides both confidentiality and integrity (AEAD). It is the standard choice for data encryption in modern systems.

**Properties:**
- Key size: 256 bits (32 bytes)
- Nonce/IV: 96 bits (12 bytes) -- MUST be unique per encryption with the same key
- Tag size: 128 bits (16 bytes) -- authentication tag
- Max plaintext per key+nonce: 2^39 - 256 bits (~64 GB)
- Max invocations per key: 2^32 (with random nonces) -- after this, nonce collision probability exceeds safety margin

**Critical nonce requirement:** Never reuse a nonce with the same key. A single nonce reuse in GCM completely breaks both confidentiality and authenticity. For high-volume systems, use AES-GCM-SIV (nonce-misuse resistant) or a deterministic nonce construction.

```python
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import os

def encrypt_aes_gcm(plaintext: bytes, key: bytes, aad: bytes = None) -> bytes:
    """
    Encrypt with AES-256-GCM.
    Returns: nonce (12 bytes) || ciphertext || tag (16 bytes)
    """
    assert len(key) == 32, "Key must be 256 bits"
    nonce = os.urandom(12)  # 96-bit random nonce
    aesgcm = AESGCM(key)
    ciphertext = aesgcm.encrypt(nonce, plaintext, aad)  # includes auth tag
    return nonce + ciphertext

def decrypt_aes_gcm(data: bytes, key: bytes, aad: bytes = None) -> bytes:
    """
    Decrypt AES-256-GCM.
    Input: nonce (12 bytes) || ciphertext || tag (16 bytes)
    """
    nonce = data[:12]
    ciphertext = data[12:]
    aesgcm = AESGCM(key)
    return aesgcm.decrypt(nonce, ciphertext, aad)
```

#### ChaCha20-Poly1305 (Software-Only / Mobile)

Preferred when AES hardware acceleration (AES-NI) is unavailable (older ARM devices, embedded systems). ~3x faster than AES-GCM in software-only implementations.

**Properties:**
- Key size: 256 bits
- Nonce: 96 bits (12 bytes) or 192 bits (XChaCha20 -- recommended for random nonces)
- Tag size: 128 bits
- No timing side channels (constant-time by design)

```go
import (
    "golang.org/x/crypto/chacha20poly1305"
    "crypto/rand"
)

func EncryptChaCha20(plaintext, key, aad []byte) ([]byte, error) {
    aead, err := chacha20poly1305.NewX(key) // XChaCha20-Poly1305 (24-byte nonce)
    if err != nil {
        return nil, err
    }

    nonce := make([]byte, aead.NonceSize()) // 24 bytes for XChaCha20
    if _, err := rand.Read(nonce); err != nil {
        return nil, err
    }

    // nonce is prepended to ciphertext
    return aead.Seal(nonce, nonce, plaintext, aad), nil
}
```

**Performance benchmarks (approximate, x86_64):**

| Algorithm | With AES-NI | Without AES-NI | ARM (no crypto ext) |
|-----------|-------------|----------------|---------------------|
| AES-256-GCM | ~4 GB/s | ~200 MB/s | ~150 MB/s |
| ChaCha20-Poly1305 | ~1.5 GB/s | ~600 MB/s | ~500 MB/s |
| AES-256-CBC + HMAC | ~2 GB/s | ~180 MB/s | ~120 MB/s |

### Asymmetric Algorithms

#### RSA-OAEP (Encryption) / RSA-PSS (Signatures)

```
Key sizes:
  2048 bits  - Minimum acceptable (NIST approved until 2030)
  3072 bits  - Recommended for new systems
  4096 bits  - High-security / long-term protection

RSA-OAEP: Optimal Asymmetric Encryption Padding
  - Use SHA-256 or SHA-384 for MGF1 hash
  - Max plaintext: key_size_bytes - 2*hash_size - 2
  - For 2048-bit key with SHA-256: max 190 bytes plaintext
  - Use for: key wrapping, small data encryption

RSA-PSS: Probabilistic Signature Scheme
  - Preferred over PKCS#1 v1.5 signatures
  - Salt length = hash length (32 bytes for SHA-256)
```

#### ECDSA / EdDSA (Signatures)

| Algorithm | Curve | Key Size | Signature Size | Security Level | Performance |
|-----------|-------|----------|----------------|----------------|-------------|
| ECDSA | P-256 (secp256r1) | 256 bits | 64 bytes | 128-bit | Good |
| ECDSA | P-384 (secp384r1) | 384 bits | 96 bytes | 192-bit | Moderate |
| EdDSA | Ed25519 | 256 bits | 64 bytes | ~128-bit | Excellent |
| EdDSA | Ed448 | 448 bits | 114 bytes | ~224-bit | Good |

**Ed25519 advantages:**
- Deterministic signatures (no random nonce -- eliminates a class of implementation bugs)
- Fastest verification of any standard signature algorithm
- Small keys (32-byte private, 32-byte public)
- Resistant to timing side channels
- Recommended for: JWT signing, SSH keys, code signing, TLS certificates

```python
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

# Key generation
private_key = Ed25519PrivateKey.generate()
public_key = private_key.public_key()

# Sign
signature = private_key.sign(b"message to sign")

# Verify
public_key.verify(signature, b"message to sign")  # raises InvalidSignature if bad
```

#### ECDH (Elliptic Curve Diffie-Hellman Key Exchange)

Used to establish shared secrets between two parties without transmitting the secret.

```
Alice                               Bob
  |                                   |
  | Generate ephemeral key pair       | Generate ephemeral key pair
  | (a, A = a*G)                      | (b, B = b*G)
  |                                   |
  |------- Send public key A -------->|
  |<------ Send public key B ---------|
  |                                   |
  | shared = a * B = a*b*G            | shared = b * A = b*a*G
  | (same point on curve)             | (same point on curve)
  |                                   |
  | derived_key = HKDF(shared, salt, info)
```

### Encryption Scope Matrix

| Scope | Method | Use Case | Performance Impact | Key Management |
|-------|--------|----------|-------------------|----------------|
| At-rest (disk/TDE) | TDE, LUKS, BitLocker | Full database/disk encryption | ~5-10% I/O | Managed by DB/OS |
| At-rest (column) | pgcrypto, AES column | Sensitive fields (SSN, CC#) | ~15-25% per query | Application manages |
| At-rest (app-level) | Envelope encryption | Maximum control, cloud-agnostic | ~20-30% per operation | KMS + local DEK |
| In-transit | TLS 1.3 | All network traffic | ~2-5% CPU | PKI / cert management |
| In-transit (payload) | JWE, NaCl box | End-to-end encrypted messages | ~10-15% | Per-user key pairs |
| Field-level (client) | Client-side FLE | PII never visible to server | ~30-50% per field | Client key management |

**Algorithm selection decision tree:**

```
Need encryption?
├── Symmetric (shared key)?
│   ├── AEAD needed? → AES-256-GCM (hardware) or ChaCha20-Poly1305 (software)
│   ├── Nonce-misuse resistant? → AES-GCM-SIV
│   └── Legacy compatibility? → AES-256-CBC + HMAC-SHA256 (encrypt-then-MAC)
├── Asymmetric (key exchange)?
│   ├── Key agreement → ECDH (X25519 preferred)
│   ├── Small data encryption → RSA-OAEP (2048+ bits)
│   └── Hybrid → ECDH + AES-GCM (TLS 1.3 model)
└── Digital signature?
    ├── Modern systems → Ed25519
    ├── Web PKI / TLS → ECDSA P-256
    ├── Legacy / FIPS → RSA-PSS (3072+ bits)
    └── Post-quantum → CRYSTALS-Dilithium (FIPS 204, draft)
```
<!-- SECTION:e1-encryption-advisor:END -->

---

<!-- SECTION:e2-key-lifecycle-planner:START -->
## 2. Key Management Lifecycle

### Key Types and Hierarchy

```
Master Key (MK)
│  - Stored in HSM or root KMS
│  - Never leaves hardware boundary
│  - Rotated: annually or on compromise
│
├── Key Encryption Key (KEK)
│   │  - Encrypts/wraps DEKs
│   │  - Stored in KMS (AWS KMS, GCP KMS, Azure Key Vault)
│   │  - Rotated: every 90-365 days
│   │
│   ├── Data Encryption Key (DEK)
│   │    - Encrypts actual data
│   │    - Unique per record/file/session
│   │    - Stored encrypted (wrapped) alongside data
│   │    - Rotated: per-use or periodic re-encryption
│   │
│   └── Token Signing Key
│        - Signs JWTs, SAML assertions
│        - Asymmetric (RS256/ES256)
│        - Rotated: every 30-90 days (JWKS endpoint)
│
└── Transport Key
     - TLS private keys
     - Rotated: with certificate renewal (90 days for Let's Encrypt)
```

### Envelope Encryption Pattern

Envelope encryption uses a two-level key hierarchy: a DEK encrypts data, and a KEK encrypts (wraps) the DEK.

```
Encryption:
1. Generate random DEK (256 bits)
2. Encrypt data with DEK using AES-256-GCM
3. Wrap (encrypt) DEK with KEK via KMS
4. Store: encrypted_data + wrapped_DEK + nonce + metadata
5. Discard plaintext DEK from memory

Decryption:
1. Read wrapped_DEK from storage
2. Unwrap DEK via KMS (authenticated request)
3. Decrypt data with plaintext DEK
4. Discard plaintext DEK from memory
```

**Implementation (AWS KMS):**

```python
import boto3
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import os, json, base64

kms_client = boto3.client('kms')
KMS_KEY_ID = 'arn:aws:kms:us-east-1:123456789:key/mrk-xxx'

def envelope_encrypt(plaintext: bytes, context: dict) -> dict:
    # 1. Generate DEK via KMS (returns both plaintext and encrypted DEK)
    response = kms_client.generate_data_key(
        KeyId=KMS_KEY_ID,
        KeySpec='AES_256',
        EncryptionContext=context  # AAD for the key wrapping
    )

    plaintext_dek = response['Plaintext']      # 32 bytes
    wrapped_dek = response['CiphertextBlob']    # encrypted DEK

    # 2. Encrypt data with plaintext DEK
    nonce = os.urandom(12)
    aesgcm = AESGCM(plaintext_dek)
    ciphertext = aesgcm.encrypt(nonce, plaintext, json.dumps(context).encode())

    # 3. Securely discard plaintext DEK
    # (In practice, Python doesn't guarantee memory clearing)

    return {
        'wrapped_dek': base64.b64encode(wrapped_dek).decode(),
        'nonce': base64.b64encode(nonce).decode(),
        'ciphertext': base64.b64encode(ciphertext).decode(),
        'encryption_context': context,
        'algorithm': 'AES-256-GCM',
        'kms_key_id': KMS_KEY_ID
    }

def envelope_decrypt(encrypted: dict) -> bytes:
    # 1. Unwrap DEK via KMS
    response = kms_client.decrypt(
        CiphertextBlob=base64.b64decode(encrypted['wrapped_dek']),
        EncryptionContext=encrypted['encryption_context']
    )
    plaintext_dek = response['Plaintext']

    # 2. Decrypt data
    aesgcm = AESGCM(plaintext_dek)
    return aesgcm.decrypt(
        base64.b64decode(encrypted['nonce']),
        base64.b64decode(encrypted['ciphertext']),
        json.dumps(encrypted['encryption_context']).encode()
    )
```

### Key Rotation Procedures

**Online rotation (zero-downtime):**

```
Phase 1: Introduce new key version (key_v2)
  - New encryptions use key_v2
  - Decryptions try key_v2 first, fall back to key_v1
  - Duration: immediate

Phase 2: Re-encryption migration (background)
  - Background job re-encrypts data from key_v1 → key_v2
  - Rate-limited to avoid overloading KMS (100 req/sec typical limit)
  - Progress tracking: re_encryption_jobs table
  - Duration: hours to weeks depending on data volume

Phase 3: Decommission old key version
  - Verify all data re-encrypted (audit query)
  - Mark key_v1 as "pending deletion"
  - Grace period: 30 days (in case of missed data)
  - Final deletion: irreversible
```

**Key version metadata schema:**

```sql
CREATE TABLE encryption_keys (
    key_id          UUID PRIMARY KEY,
    key_version     INT NOT NULL,
    kms_key_arn     VARCHAR(500) NOT NULL,
    status          VARCHAR(20) NOT NULL,  -- 'active', 'decrypt_only', 'pending_deletion'
    created_at      TIMESTAMP NOT NULL,
    rotated_at      TIMESTAMP,
    expires_at      TIMESTAMP,
    re_encrypt_done BOOLEAN DEFAULT FALSE
);
```

### HSM Integration (PKCS#11)

```
HSM (Hardware Security Module):
  - FIPS 140-2 Level 3 or Level 4 certified
  - Master keys NEVER leave HSM boundary
  - All crypto operations performed inside HSM
  - Tamper-evident / tamper-resistant hardware

Common HSMs:
  - AWS CloudHSM (FIPS 140-2 Level 3)
  - Azure Dedicated HSM (Thales Luna)
  - GCP Cloud HSM (FIPS 140-2 Level 3)
  - On-premises: Thales Luna, Utimaco
```

### Cloud KMS Comparison

| Feature | AWS KMS | GCP Cloud KMS | Azure Key Vault |
|---------|---------|---------------|-----------------|
| Key types | Symmetric, RSA, ECC | Symmetric, RSA, ECC, Ed25519 | RSA, ECC, Symmetric |
| HSM backing | CloudHSM option | Automatic for all keys | Dedicated HSM tier |
| Auto-rotation | Annual (symmetric only) | Configurable period | Configurable |
| Multi-region | MRK (multi-region keys) | Global keys | Managed HSM replication |
| Pricing | $1/key/month + $0.03/10K req | $0.06/key version/month | $1-5/key/month |
| Max requests | 5,500-30,000/sec (varies) | 60,000/sec (project) | 2,000/sec (vault) |
| FIPS level | 140-2 Level 2 (default) | 140-2 Level 3 | 140-2 Level 2/3 |

### Key Escrow for Disaster Recovery

```
Escrow Strategy:
1. Generate master key in HSM
2. Export master key wrapped with escrow key (ceremony with M-of-N key holders)
3. Split escrow key using Shamir's Secret Sharing (e.g., 3-of-5 threshold)
4. Distribute shares to geographically separated custodians
5. Store wrapped master key in secure offline storage (vault, safe deposit box)

Recovery Procedure:
1. Assemble minimum threshold of key custodians (3 of 5)
2. Reconstruct escrow key from shares (in secure environment)
3. Unwrap master key
4. Import to new HSM
5. Destroy reconstructed escrow key and shares
6. Generate new escrow with new shares (rotate after recovery)
```
<!-- SECTION:e2-key-lifecycle-planner:END -->

---

<!-- SECTION:e3-tls-configurator:START -->
## 3. TLS/mTLS Configuration

### TLS 1.3 Overview

TLS 1.3 (RFC 8446) significantly simplifies the handshake (1-RTT vs 2-RTT in TLS 1.2) and removes insecure algorithms.

**Removed from TLS 1.3:**
- RSA key exchange (no forward secrecy)
- CBC mode ciphers (padding oracle attacks)
- RC4, DES, 3DES
- SHA-1 in signatures
- Static DH/ECDH (no forward secrecy)
- Compression (CRIME attack)

**TLS 1.3 cipher suites (only 5):**

| Cipher Suite | Key Exchange | Encryption | Hash |
|-------------|-------------|------------|------|
| TLS_AES_256_GCM_SHA384 | ECDHE | AES-256-GCM | SHA-384 |
| TLS_AES_128_GCM_SHA256 | ECDHE | AES-128-GCM | SHA-256 |
| TLS_CHACHA20_POLY1305_SHA256 | ECDHE | ChaCha20-Poly1305 | SHA-256 |
| TLS_AES_128_CCM_SHA256 | ECDHE | AES-128-CCM | SHA-256 |
| TLS_AES_128_CCM_8_SHA256 | ECDHE | AES-128-CCM-8 | SHA-256 |

### Nginx TLS Configuration (Production Hardened)

```nginx
server {
    listen 443 ssl http2;
    server_name example.com;

    # Certificates
    ssl_certificate     /etc/nginx/ssl/example.com.fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/example.com.privkey.pem;

    # Protocol versions
    ssl_protocols TLSv1.2 TLSv1.3;  # TLS 1.2 still needed for older clients

    # Cipher suites (TLS 1.2 -- TLS 1.3 ciphers are not configurable in nginx)
    ssl_ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;  # Let client choose (modern best practice)

    # ECDH curve
    ssl_ecdh_curve X25519:secp384r1:secp256r1;

    # Session resumption
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;  # Disable for forward secrecy

    # OCSP stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/nginx/ssl/chain.pem;
    resolver 1.1.1.1 8.8.8.8 valid=300s;
    resolver_timeout 5s;

    # Security headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
}
```

### Envoy Proxy TLS Configuration

```yaml
static_resources:
  listeners:
    - name: https_listener
      address:
        socket_address: { address: 0.0.0.0, port_value: 443 }
      filter_chains:
        - transport_socket:
            name: envoy.transport_sockets.tls
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.DownstreamTlsContext
              common_tls_context:
                tls_params:
                  tls_minimum_protocol_version: TLSv1_2
                  tls_maximum_protocol_version: TLSv1_3
                  cipher_suites:
                    - ECDHE-ECDSA-AES256-GCM-SHA384
                    - ECDHE-RSA-AES256-GCM-SHA384
                    - ECDHE-ECDSA-CHACHA20-POLY1305
                  ecdh_curves:
                    - X25519
                    - P-256
                tls_certificates:
                  - certificate_chain: { filename: "/etc/envoy/ssl/cert.pem" }
                    private_key: { filename: "/etc/envoy/ssl/key.pem" }
                alpn_protocols: ["h2", "http/1.1"]
              require_client_certificate: false  # Set true for mTLS
```

### mTLS Setup (Mutual TLS)

mTLS requires both server and client to present certificates, providing mutual authentication.

**Certificate hierarchy:**

```
Root CA (offline, air-gapped)
├── Intermediate CA (server certificates)
│   ├── server-a.example.com
│   └── server-b.example.com
└── Intermediate CA (client certificates)
    ├── service-account-payments
    ├── service-account-orders
    └── service-account-users
```

**Client certificate generation (OpenSSL):**

```bash
# 1. Generate client private key
openssl ecparam -genkey -name prime256v1 -out client.key

# 2. Generate CSR
openssl req -new -key client.key -out client.csr \
  -subj "/CN=service-payments/O=ExampleCorp/OU=Engineering"

# 3. Sign with intermediate CA
openssl x509 -req -in client.csr \
  -CA intermediate-ca.pem -CAkey intermediate-ca-key.pem \
  -CAcreateserial -out client.pem \
  -days 365 -sha256 \
  -extfile <(cat <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage=digitalSignature
extendedKeyUsage=clientAuth
subjectAltName=URI:spiffe://example.com/service/payments
EOF
)

# 4. Verify certificate chain
openssl verify -CAfile root-ca.pem -untrusted intermediate-ca.pem client.pem
```

**Nginx mTLS configuration:**

```nginx
server {
    listen 443 ssl http2;

    # Server certificate (standard)
    ssl_certificate     /etc/nginx/ssl/server.pem;
    ssl_certificate_key /etc/nginx/ssl/server.key;

    # Client certificate verification
    ssl_client_certificate /etc/nginx/ssl/client-ca-chain.pem;
    ssl_verify_client on;           # Require client cert (use 'optional' for mixed)
    ssl_verify_depth 2;             # Max chain depth to verify

    # CRL checking
    ssl_crl /etc/nginx/ssl/client-ca.crl;

    # Pass client cert info to backend
    location / {
        proxy_set_header X-Client-CN $ssl_client_s_dn_cn;
        proxy_set_header X-Client-Serial $ssl_client_serial;
        proxy_set_header X-Client-Verify $ssl_client_verify;
        proxy_pass http://backend;
    }
}
```

### OCSP Stapling Configuration

OCSP stapling eliminates the need for clients to contact the CA to check certificate revocation, improving performance and privacy.

```nginx
# Nginx OCSP stapling
ssl_stapling on;
ssl_stapling_verify on;
ssl_trusted_certificate /etc/nginx/ssl/fullchain.pem;  # includes intermediate CA

# Verify OCSP stapling is working
# openssl s_client -connect example.com:443 -status < /dev/null 2>&1 | grep -A 5 "OCSP"
```

### Certificate Pinning Best Practices

```
WARNING: Certificate pinning is high-risk. Mis-configuration can
permanently lock users out. Consider alternatives first.

Recommended approach: Pin the intermediate CA (not the leaf cert)
  - Survives leaf cert rotation
  - Still protects against rogue CA attacks

HTTP Public Key Pinning (HPKP): DEPRECATED (removed from browsers)
  - Too risky: mis-pinning = site permanently unreachable

Modern alternative: Certificate Transparency (CT) logs
  - Detect mis-issued certificates via public CT log monitoring
  - Use: Expect-CT header or CT enforcement in CAA DNS records

Mobile app pinning (still relevant):
  - Pin against backup keys (at least 2 pins)
  - Include emergency bypass mechanism (remote config)
  - Set reasonable max-age (30 days, not years)
```

### Let's Encrypt / cert-manager Automation

**cert-manager (Kubernetes):**

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: certs@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-account
    solvers:
      - http01:
          ingress:
            class: nginx
      - dns01:
          cloudDNS:
            project: my-gcp-project
            serviceAccountSecretRef:
              name: clouddns-sa
              key: key.json

---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-com
  namespace: production
spec:
  secretName: example-com-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - example.com
    - "*.example.com"
  duration: 2160h      # 90 days
  renewBefore: 720h    # Renew 30 days before expiry
  privateKey:
    algorithm: ECDSA
    size: 256
```
<!-- SECTION:e3-tls-configurator:END -->

---

<!-- SECTION:e4-secret-manager:START -->
## 4. Secret Management Patterns

### HashiCorp Vault Architecture

**Core concepts:**

```
┌──────────────────────────────────────────────┐
│                 Vault Server                  │
│                                              │
│  ┌─────────┐  ┌──────────┐  ┌─────────────┐ │
│  │  Auth    │  │  Secret  │  │   Audit     │ │
│  │ Methods  │  │ Engines  │  │   Devices   │ │
│  │          │  │          │  │             │ │
│  │ - Token  │  │ - KV v2  │  │ - File      │ │
│  │ - AppRole│  │ - Transit│  │ - Syslog    │ │
│  │ - K8s   │  │ - PKI    │  │ - Socket    │ │
│  │ - OIDC  │  │ - DB     │  │             │ │
│  │ - AWS   │  │ - SSH    │  │             │ │
│  └─────────┘  └──────────┘  └─────────────┘ │
│                                              │
│  ┌─────────────────────────────────────────┐ │
│  │         Storage Backend                  │ │
│  │  (Consul / Raft / DynamoDB / GCS)       │ │
│  └─────────────────────────────────────────┘ │
│                                              │
│  ┌─────────────────────────────────────────┐ │
│  │         Seal / Unseal Mechanism          │ │
│  │  (Shamir / AWS KMS / Transit Auto-Unseal)│ │
│  └─────────────────────────────────────────┘ │
└──────────────────────────────────────────────┘
```

**Seal/Unseal process:**

```
Initialization (one-time):
  vault operator init -key-shares=5 -key-threshold=3
  → Generates 5 unseal keys + initial root token
  → Store unseal keys with separate custodians

Unseal (after restart):
  vault operator unseal <key-1>   # 1 of 3
  vault operator unseal <key-2>   # 2 of 3
  vault operator unseal <key-3>   # 3 of 3 → Vault is unsealed

Auto-unseal (recommended for production):
  # vault.hcl
  seal "awskms" {
    region     = "us-east-1"
    kms_key_id = "alias/vault-auto-unseal"
  }
  # Vault automatically unseals on restart using AWS KMS
```

**Auth methods configuration:**

```hcl
# AppRole (for applications/services)
resource "vault_auth_backend" "approle" {
  type = "approle"
}

resource "vault_approle_auth_backend_role" "payments_service" {
  backend        = vault_auth_backend.approle.path
  role_name      = "payments-service"
  token_ttl      = 3600    # 1 hour
  token_max_ttl  = 14400   # 4 hours
  token_policies = ["payments-read", "payments-write"]

  # Security: bind to CIDR and secret ID
  secret_id_bound_cidrs = ["10.0.0.0/24"]
  token_bound_cidrs     = ["10.0.0.0/24"]
  secret_id_num_uses    = 1  # One-time use secret ID
}

# Kubernetes auth (for pods)
resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
}

resource "vault_kubernetes_auth_backend_config" "config" {
  backend            = vault_auth_backend.kubernetes.path
  kubernetes_host    = "https://kubernetes.default.svc"
  kubernetes_ca_cert = file("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")
}

resource "vault_kubernetes_auth_backend_role" "api_service" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "api-service"
  bound_service_account_names      = ["api-service"]
  bound_service_account_namespaces = ["production"]
  token_ttl                        = 3600
  token_policies                   = ["api-secrets"]
}
```

**Secret engines:**

```bash
# KV v2 (versioned key-value store)
vault kv put secret/myapp/config \
  db_host="db.prod.internal" \
  db_port="5432" \
  api_key="sk_live_xxx"

vault kv get -version=2 secret/myapp/config  # Read specific version
vault kv rollback -version=1 secret/myapp/config  # Rollback

# Transit (encryption as a service -- keys never leave Vault)
vault write transit/encrypt/my-key plaintext=$(echo "sensitive" | base64)
# → ciphertext: vault:v1:AbCdEf...

vault write transit/decrypt/my-key ciphertext="vault:v1:AbCdEf..."
# → plaintext: (base64-encoded "sensitive")

# Dynamic database credentials
vault write database/config/mydb \
  plugin_name=postgresql-database-plugin \
  connection_url="postgresql://{{username}}:{{password}}@db:5432/mydb" \
  allowed_roles="readonly,readwrite" \
  username="vault_admin" \
  password="admin_password"

vault write database/roles/readonly \
  db_name=mydb \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"

# Request dynamic credentials
vault read database/creds/readonly
# → username: v-approle-readonly-abc123
# → password: A1B2C3D4... (auto-revoked after TTL)
```

### AWS Secrets Manager Patterns

```python
import boto3
import json

secrets_client = boto3.client('secretsmanager')

# Store secret with automatic rotation
secrets_client.create_secret(
    Name='prod/myapp/database',
    SecretString=json.dumps({
        'host': 'db.prod.internal',
        'port': 5432,
        'username': 'app_user',
        'password': 'initial_password',
        'dbname': 'myapp'
    }),
    Tags=[
        {'Key': 'Environment', 'Value': 'production'},
        {'Key': 'Application', 'Value': 'myapp'}
    ]
)

# Configure automatic rotation (Lambda-based)
secrets_client.rotate_secret(
    SecretId='prod/myapp/database',
    RotationLambdaARN='arn:aws:lambda:us-east-1:123456789:function:rotate-db-password',
    RotationRules={'AutomaticallyAfterDays': 30}
)

# Retrieve secret (with caching for performance)
from aws_secretsmanager_caching import SecretCache

cache = SecretCache()

def get_db_config():
    secret = cache.get_secret_string('prod/myapp/database')
    return json.loads(secret)
```

### Kubernetes Secrets Integration

**External Secrets Operator (ESO):**

```yaml
# Connect to external secret store
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: production
spec:
  provider:
    vault:
      server: "https://vault.internal:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "api-service"
          serviceAccountRef:
            name: "api-service"

---
# Sync external secret to Kubernetes Secret
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: api-config
  namespace: production
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: api-config           # K8s Secret name
    creationPolicy: Owner
    template:
      type: Opaque
      data:
        DB_HOST: "{{ .db_host }}"
        DB_PASSWORD: "{{ .db_password }}"
        API_KEY: "{{ .api_key }}"
  data:
    - secretKey: db_host
      remoteRef:
        key: myapp/config
        property: db_host
    - secretKey: db_password
      remoteRef:
        key: myapp/config
        property: db_password
    - secretKey: api_key
      remoteRef:
        key: myapp/config
        property: api_key
```

### The Secret Zero Problem and Solutions

The "secret zero" problem: how does an application authenticate to the secret manager in the first place?

```
Problem:
  App needs credentials → stored in secret manager → need credentials to access secret manager → ???

Solutions by environment:

1. Cloud-native (AWS/GCP/Azure):
   - Use instance metadata / IAM roles (no static credentials)
   - AWS: EC2 instance role, ECS task role, Lambda execution role
   - GCP: Service account attached to instance/pod (Workload Identity)
   - Azure: Managed Identity

2. Kubernetes:
   - Workload Identity (GKE) / IRSA (EKS) / Pod Identity (AKS)
   - ServiceAccount token projected into pod → exchanged for Vault/KMS token
   - No static credentials in cluster

3. CI/CD:
   - OIDC federation: CI provider (GitHub Actions, GitLab CI) issues JWT
   - JWT exchanged for cloud provider credentials (no stored secrets)
   - Example: GitHub Actions → AWS STS AssumeRoleWithWebIdentity

4. On-premises / VM:
   - Response wrapping: Vault wraps secret in single-use token, delivered out-of-band
   - Trusted platform: TPM-based attestation
   - Configuration management: Ansible Vault, Chef encrypted data bags (bootstrap only)
```

**GitHub Actions OIDC federation example (no stored secrets):**

```yaml
# .github/workflows/deploy.yml
permissions:
  id-token: write  # Required for OIDC
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789:role/github-deploy
          aws-region: us-east-1
          # No access key ID or secret key needed!
          # GitHub's OIDC token is exchanged for temporary AWS credentials

      - name: Access secrets
        run: |
          # Now authenticated via OIDC -- fetch secrets from Secrets Manager
          aws secretsmanager get-secret-value --secret-id prod/myapp/config
```
<!-- SECTION:e4-secret-manager:END -->
