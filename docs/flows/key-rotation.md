# Flow — Field-cipher key rotation

Rotating the `FIELD_CIPHER_KEY` without downtime or data loss, across both
`core-api` (producer) and `notifier` (consumer).

```mermaid
sequenceDiagram
    autonumber
    actor Op as Operator
    participant K8s as Kubernetes
    participant API as core-api
    participant N as notifier
    participant Kafka

    Note over Op,Kafka: Phase 1 — provision v2, dual-decrypt window
    Op->>K8s: kubectl create secret ... FIELD_CIPHER_KEY_V2=<new>
    Op->>K8s: patch deployments → mount BOTH v1 and v2 keys
    K8s->>API: rolling restart (keys: {v1, v2}, active: v1)
    K8s->>N:   rolling restart (keys: {v1, v2}, active: v1)
    Note over API,N: At this point both can decrypt v1 AND v2;<br/>both still ENCRYPT with v1.

    Note over Op,Kafka: Phase 2 — flip producer to v2
    Op->>K8s: patch core-api → active_version: v2
    K8s->>API: rolling restart (keys: {v1, v2}, active: v2)
    API->>Kafka: new users.v1 messages encrypted with v2
    Note over N: still decrypts both (mixed traffic)

    Note over Op,Kafka: Phase 3 — replay & rewrite (one-shot)
    Op->>K8s: kubectl create job replay-users-v1-rewrite
    K8s->>API: replay job reads all users.v1 keys,<br/>decrypts (with whichever key works),<br/>re-encrypts under v2, publishes new tombstone+upsert pair
    Note over Kafka: After replay, only v2 ciphertexts in the topic<br/>(log compaction drops the old v1 versions)

    Note over Op,Kafka: Phase 4 — retire v1
    Op->>K8s: patch deployments → mount ONLY v2 key
    K8s->>API: rolling restart (keys: {v2}, active: v2)
    K8s->>N:   rolling restart (keys: {v2}, active: v2)
    Op->>K8s: delete Secret FIELD_CIPHER_KEY_V1
```

## Pre-flight checklist

- [ ] Generate new key: `openssl rand -base64 32`
- [ ] Store it in the secrets backend (External Secrets / sealed-secrets / etc.)
- [ ] Verify all running pods can read both keys (`kubectl exec ... env | grep FIELD_CIPHER`)
- [ ] Have the replay job tested in staging first

## Rollback at any phase

| Phase reached | Rollback step |
|---|---|
| After Phase 1 | Remove v2 key from deployments; redeploy. Nothing was written with v2 yet — no data loss. |
| After Phase 2 | Flip producer back to `active_version: v1`. Mixed-encryption stays until next replay; consumer still decrypts both. |
| After Phase 3 | Once replayed, every message is v2-encrypted. Rollback requires re-replaying with the old key — make sure you keep v1 mounted until you're confident. |
| After Phase 4 | v1 is gone. No rollback. Treat this as a permanent step. |

## Why this approach

- **No coordinated stop** — apps roll restart, consumers don't see gaps
- **No "encrypted with unknown key" errors** — every running pod has every key it might encounter
- **Audited** — every step is a `kubectl` operation, captured by Kubernetes' own audit log
