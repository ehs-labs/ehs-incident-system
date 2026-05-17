# ADR-0004: Field-level encryption of PII in users.v1

- **Status:** Accepted
- **Date:** 2026-05-17

## Context

The `users.v1` CDC topic carries `email`, `name`, `telegram_chat_id` — actual PII.
Kafka's standard protections (TLS, SASL/ACLs, at-rest encryption) defend the
network, the auth layer, and the disks — but a misconfigured ACL, a future
analytics consumer with read-all access, or a malicious cluster admin would all
see plaintext PII.

EHS data is sensitive (injury narratives, witness names) — we want a higher
bar than "trust the broker operators."

## Decision

PII fields in `users.v1` are encrypted at the field level with **AES-256-GCM**
via a shared Ruby gem (`ehs-envelope`). Key in K8s Secret `field-cipher-key`;
versioned wire format (`v1:nonce:ct:tag`) supports rotation.

Domain topics (`incidents.v1`, etc.) carry **no PII** at all — only
`recipient_user_ids` and operational fields.

## Consequences

**Wins**
- A compromised broker / ACL gap / curious admin sees ciphertext for PII
- Audit story is strong: "PII is encrypted *before* it crosses the service boundary"
- Key rotation is a well-defined procedure (see `docs/flows/key-rotation.md`)

**Costs**
- One more secret to manage across two services
- Notifier needs the key — if the key disk fails, the mirror is unusable until restored from the source topic (which is the right behavior, but worth knowing)
- Slight CPU cost per encrypt/decrypt (negligible at our throughput)
