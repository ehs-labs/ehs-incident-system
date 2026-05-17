# Event schemas (Avro)

Shared event contracts between `core-api` (producer) and `notifier` (consumer).
Registered with **Karapace** (open-source Apache-2 schema registry, drop-in for
Confluent Schema Registry) on app boot.

## Topics

| Topic | Key | Schemas |
|---|---|---|
| `incidents.v1` | `org_id` | `incident_submitted`, `incident_assigned`, `incident_closed` |
| `corrective_actions.v1` | `org_id` | `corrective_action_assigned`, `corrective_action_overdue` |
| `users.v1` (log-compacted) | `user_id` | `user_upserted` |
| `system.v1` | `org_id` | `sla_breached` |

## Wire format

Confluent wire format: `0x00 + <4-byte big-endian schema_id> + <Avro binary>`.

This is the universal Kafka ecosystem convention — Kafka UI's "Avro" mode pretty-prints messages out of the box.

## Compatibility policy

Configured at the registry level: **`BACKWARD`** (new schema can read old data).
- Adding optional fields with defaults → OK
- Removing fields that have defaults → OK
- Renaming → NOT OK (use aliases)
- Type narrowing → NOT OK
- Type widening (e.g. `int` → `long`) → OK

Incompatible publishes are rejected by Karapace at registration time.

## PII discipline

Domain events (`incidents.v1`, `corrective_actions.v1`, `system.v1`) carry
**only `recipient_user_ids` and operational fields** — never email, phone,
telegram_chat_id. Consumers resolve recipient identities through the
`users.v1` mirror.

`users.v1` itself carries PII fields, but they're **encrypted at the field
level** by `ehs-envelope` (AES-256-GCM) using a shared symmetric key. A
compromise of Kafka topic data does not leak readable PII.

## Adding a new event

1. Drop a `.avsc` file in this directory.
2. The next CI run validates that it registers cleanly against Karapace under the configured compatibility policy.
3. `bootstrap.sh` registers it on the next local run.
4. Add a producer call in `core-api` (typically from an AASM `after_transition` callback).
5. Add a consumer handler in `notifier/app/handlers/`.
