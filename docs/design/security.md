# Security

## Auth model

```mermaid
sequenceDiagram
    autonumber
    participant Browser
    participant CoreApi as core-api
    participant DB as ehs_app

    Browser->>CoreApi: POST /api/v1/auth/login (email, password)
    CoreApi->>DB: bcrypt verify; check confirmed_at, locked_at, deleted_at
    DB-->>CoreApi: user
    CoreApi-->>Browser: 200 + Authorization: Bearer <jwt> + refresh-cookie

    Browser->>CoreApi: GET /api/v1/incidents (Authorization: Bearer ...)
    CoreApi->>CoreApi: verify JWT (HS256, JWT_SECRET); check denylist
    CoreApi-->>Browser: 200 + data
```

**Two tokens:**
- **Access token** — JWT (HS256), 15 min, in memory only on the SPA (not localStorage — XSS hygiene)
- **Refresh token** — opaque, 7 days, in an `HttpOnly; Secure; SameSite=Lax` cookie. Used only to mint a new access token.

**Revocation:** logout adds the JWT's `jti` to a denylist table; every request checks it (Devise's standard pattern).

## Roles and authorization

[Pundit](https://github.com/varvet/pundit) policies — one class per resource, one method per action. Three roles: `worker`, `investigator`, `admin`.

| Resource | Worker | Investigator | Admin |
|---|---|---|---|
| Incidents (own) | CRU | CRU | CRUD |
| Incidents (others' in same site) | R | CRU | CRUD |
| Incidents (other sites) | – | R (if site member) | CRUD |
| Corrective actions assigned to self | RU | RU | CRUD |
| Users | – | – | CRUD |
| Sites | – | R | CRUD |

Tenant scoping is enforced by Pundit `Scope` classes: every collection query is automatically filtered to the current user's organization.

## Kafka — defense in depth (four layers)

| Layer | Mechanism | What it defeats |
|---|---|---|
| 1. TLS in-flight | Broker listeners with cert-manager certs | Network sniffing between clients and brokers |
| 2. SASL/SCRAM + ACLs | One principal per app role (`api-producer`, `notifier-consumer`, `notifier-cdc-consumer`); ACLs grant least privilege | Future analytics/BI consumer accidentally getting `users.v1` access |
| 3. Encryption at rest | Encrypted PVCs (LUKS / cloud KMS) | Stolen disks, backup leaks |
| 4. Field-level encryption | `ehs-envelope` (AES-256-GCM); PII fields in `users.v1` only | Malicious cluster admin browsing topics; misconfigured ACLs |

The four layers are independent — defeating any three doesn't compromise PII because layer 4 still applies.

### Wire format for encrypted fields

```
v<key_version>:<nonce_b64>:<ciphertext_b64>:<tag_b64>
```

- `v1` is the active key version at MVP
- Rotation procedure: documented in [`docs/operations/key-rotation.md`](../operations/key-rotation.md)
- Algorithm: AES-256-GCM (authenticated encryption — tampering is detected)

## Threat model — primary threats addressed

| Threat | Mitigation |
|---|---|
| Stolen JWT (XSS, malicious extension) | Short expiry (15m); denylist on logout; refresh cookie is `HttpOnly` |
| SQL injection | ActiveRecord parameterized queries; Brakeman in CI |
| CSRF | Refresh endpoint is the only cookie-authenticated mutation; `SameSite=Lax`; CORS allowlist |
| Mass-assignment | Strong params on every controller |
| Tenant cross-contamination | Pundit `Scope` enforces `org_id` filter on every collection |
| Replay of email confirmation / invitation tokens | Single-use tokens; expire in 3 days (Devise defaults) |
| PII leak via Kafka | Field-level encryption (above) |
| Pending-migration deploys | Boot-time tripwire — refuses to serve traffic against wrong schema |

## What's deferred (documented as ADRs)

- **SSO/SAML/OIDC** — ADR-0008. Required for enterprise EHS customers; not in MVP.
- **WAF, DDoS protection** — sits in front of the ingress in cloud overlay; not modeled here.
- **Audit log shipping to a separate immutable store** — current PaperTrail in the app DB is good enough for MVP; production-EHS would ship to a tamper-evident log.
