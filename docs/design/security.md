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

---

## Kafka SASL_SSL wiring — cloud overlay

### Secrets added to `k8s/overlays/cloud/`

| Secret name | Purpose | Who mounts it |
|---|---|---|
| `kafka-credentials` | KAFKA_SECURITY_PROTOCOL, KAFKA_SASL_MECHANISM, KAFKA_SASL_USERNAME, KAFKA_SASL_PASSWORD, KAFKA_TLS_CA_FILE | core-api, sidekiq, notifier, notifier-karafka (via envFrom) |
| `kafka-ca-cert` | CA certificate PEM for broker TLS verification; mounted at `/etc/kafka/ssl/ca.crt` | same four deployments (volume) |
| `kafka-admin-credentials` | Bootstrap-only admin principal; consumed only by the kafka-bootstrap Job | kafka-bootstrap Job |

Placeholder values (`REPLACE_ME`) ship in git. Real values must be injected at deploy time via External Secrets Operator, Sealed Secrets, or a CI-managed `kubectl create secret --dry-run=client -o yaml | kubectl apply -f -` step. **Never commit real credentials.**

### Credential rotation procedure

Follow the general key rotation process in [`docs/operations/key-rotation.md`](../operations/key-rotation.md) for the symmetric-key layer. For Kafka SCRAM credentials specifically:

1. Generate a new password for the principal being rotated (e.g. `core-api`).
2. Add the new password as an additional SCRAM credential:
   ```
   kafka-configs.sh --bootstrap-server <broker> \
     --command-config admin.properties \
     --alter \
     --add-config 'SCRAM-SHA-512=[password=<new>]' \
     --entity-type users --entity-name core-api
   ```
3. Update the `kafka-credentials` Secret in the cluster (ESO will re-sync, or apply the updated Sealed Secret).
4. Perform a rolling restart of core-api and sidekiq to pick up the new env var.
5. Once all pods are running on the new credential, remove the old SCRAM entry:
   ```
   kafka-configs.sh --bootstrap-server <broker> \
     --command-config admin.properties \
     --alter \
     --delete-config 'SCRAM-SHA-512' \
     --entity-type users --entity-name core-api
   ```
   Then immediately re-add only the new one (step 2 with the new password) to keep the entry current.

### ACL matrix

| Principal | Topic | Allow | Deny |
|---|---|---|---|
| core-api | incidents.v1 | Write, Describe | — |
| core-api | corrective_actions.v1 | Write, Describe | — |
| core-api | system.v1 | Write, Describe | — |
| core-api | users.v1 | — | Read (explicit DENY) |
| notifier | incidents.v1 | Read, Describe | Write |
| notifier | corrective_actions.v1 | Read, Describe | Write |
| notifier | users.v1 | Read, Describe | Write |
| notifier | system.v1 | Read, Describe | Write |
| notifier | consumer-group: domain_events | Read | — |
| notifier | consumer-group: reference_data | Read | — |
| notifier | consumer-group: notifier | Read | — |

The explicit DENY on `core-api` + `users.v1` Read takes precedence over any future wildcard allow, providing defense-in-depth against misconfiguration.

### Verifying ACLs in a live cluster

```bash
# List all ACLs on a specific topic:
kafka-acls.sh --bootstrap-server <broker>:9092 \
  --command-config /path/to/admin.properties \
  --list \
  --topic incidents.v1

# List all ACLs for a specific principal:
kafka-acls.sh --bootstrap-server <broker>:9092 \
  --command-config /path/to/admin.properties \
  --list \
  --principal User:core-api
```

Where `admin.properties` contains:
```
security.protocol=SASL_SSL
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="<admin>" password="<password>";
ssl.ca.location=/etc/kafka/ssl/ca.crt
```

### kafka-bootstrap Job — idempotency and re-runs

The Job (`k8s/overlays/cloud/kafka-bootstrap.job.yaml`) is one-shot but safe to re-run:

- SCRAM user creation uses `--add-config` which upserts — re-running overwrites with the same password (no-op if unchanged).
- Topic creation uses `--if-not-exists` — skips existing topics.
- ACL creation is idempotent — Kafka ignores duplicate ACL entries.

To re-run after a failed bootstrap or a manual cluster reset:

```bash
kubectl -n ehs delete job kafka-bootstrap
kubectl -n ehs apply -f k8s/overlays/cloud/kafka-bootstrap.job.yaml
```

The Job has `ttlSecondsAfterFinished: 600` — the completed pod is cleaned up automatically after 10 minutes. `backoffLimit: 3` means Kubernetes retries up to three times before marking the Job as failed.

---

## Encryption Verification

This section documents how field-level encryption on `users.v1` was verified end-to-end, and the expected failure mode when the cipher key is absent or wrong.

### Confirming ciphertext on the wire

Trigger a `UserUpserted` event by mutating a user through the Rails runner:

```bash
docker compose exec core-api bin/rails runner "
  u = User.first
  u.update!(name: 'Cipher Test Name')
  puts 'updated user id=' + u.id.to_s
"
```

Wait a few seconds for `OutboxShipperJob` (Sidekiq) to drain, then consume from the topic and hex-dump the bytes:

```bash
docker compose exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic users.v1 \
  --from-beginning \
  --max-messages 1 \
  --property print.key=true \
  --property print.headers=true \
  2>/dev/null | xxd
```

A verified run produced the following output (event_id `01KRV67CN2ZVE9X7R3HTP8NF3F`, user_id 27):

```
00000000: 6576 656e 745f 7479 7065 3a55 7365 7255  event_type:UserU
00000010: 7073 6572 7465 642c 6576 656e 745f 6964  pserted,event_id
00000020: 3a30 314b 5256 3637 434e 325a 5645 3958  :01KRV67CN2ZVE9X
00000030: 3752 3348 5450 384e 4633 4609 3237 0900  7R3HTP8NF3F.27..
00000040: 0000 000e 0432 3704 3136 028a 0176 313a  .....27.16...v1:
00000050: 366c 566b 4737 707a 335a 5961 344f 3339  6lVkG7pz3ZYa4O39
00000060: 3a47 6c52 4947 6477 6563 6c72 4e39 6b70  :GlRIGdweclrN9kp
00000070: 3353 3150 3936 413d 3d3a 7369 3743 4350  3S1P96A==:si7CCP
00000080: 7542 2f56 324a 714a 6c72 484c 5459 3277  uB/V2JqJlrHLTY2w
00000090: 3d3d 9a01 7631 3a38 7a6f 4848 7441 546c  ==..v1:8zoHHtATl
000000a0: 4274 376d 3045 563a 324e 4f4e 4b75 525a  Bt7m0EV:2NONKuRZ
000000b0: 3653 5a42 706f 5272 684e 4234 3658 4b57  6SZBpoRrhNB46XKW
000000c0: 692b 5a61 4d67 3d3d 3a4f 376f 6a48 712b  i+ZaMg==:O7ojHq+
000000d0: 7050 4d37 3267 656b 5450 7475 564b 673d  pPM72gekTPtuVKg=
000000e0: 3d00 0000 cea2 9fe5 c667 0a              =........g.
```

The `v1:` prefix first appears at byte offset `0x4e` (`name_enc`) and again at `0x96` (`email_enc`). Neither field is human-readable plaintext — AES-256-GCM encryption is confirmed on the wire. A raw copy of this output is saved to `docs/design/screenshots/users-v1-ciphertext.txt`.

### Missing or wrong key — expected failure mode

When `FIELD_CIPHER_KEY` is absent or incorrect the notifier's `UsersConsumer` will raise on the first `users.v1` message it tries to decrypt:

```
Ehs::Envelope::MalformedCiphertext
```

This is an authenticated-encryption tag mismatch — OpenSSL raises `OpenSSL::Cipher::CipherError` which `Ehs::Envelope::Cipher#decrypt` re-raises as `MalformedCiphertext`. The consumer re-raises from its `rescue` block, which causes Karafka to mark the offset as unprocessed and log the error:

```
[UsersConsumer] failed offset=<n>: Ehs::Envelope::MalformedCiphertext: <openssl message>
```

Karafka's default error handling will retry the batch according to the topic's `max_wait_time` / DLQ policy, and the process will remain up (crash loops only occur if the consumer is configured with `raise_on_unexpected_status: true` at the app level).

This behaviour is verified by the smoke spec at `notifier/spec/encryption_smoke_spec.rb`:

```bash
docker compose exec notifier bundle exec rspec spec/encryption_smoke_spec.rb \
  --format documentation
```

Expected output (5 examples, 0 failures):

```
users.v1 envelope encryption
  encrypts to the versioned wire format
  decrypts back to the original plaintext with the correct key
  raises on decryption with the wrong key
  returns nil for nil plaintext
  returns nil for nil wire value
```

The wrong-key example (`raises on decryption with the wrong key`) directly asserts `Ehs::Envelope::MalformedCiphertext` — the same exception that surfaces in production when `FIELD_CIPHER_KEY` is misconfigured.
