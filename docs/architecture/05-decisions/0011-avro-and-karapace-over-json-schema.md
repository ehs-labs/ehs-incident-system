# ADR-0011: Avro + Karapace over JSON Schema for event contracts

- **Status:** Accepted
- **Date:** 2026-05-17

## Context

Events need a contract between producer (core-api) and consumer (notifier). Two
mainstream choices:

- **JSON Schema** — text payloads, schema validation in code
- **Avro + a Schema Registry** — binary payloads, schema evolution enforced by the registry

## Decision

Use **Avro** with **Karapace** (open-source Apache-2 schema registry,
drop-in for Confluent Schema Registry). Compatibility policy: `BACKWARD`.

## Consequences

**Wins**
- Karapace enforces compatibility at registration time — incompatible schema
  changes fail CI, not production
- Compact binary payloads — smaller messages, less network/disk
- Standard Kafka ecosystem tooling (kafka-ui, kcat with `-s avro`) recognizes the wire format
- Resume signal: "Schema Registry" is a known phrase in every Kafka job posting

**Costs**
- Extra service (Karapace) to operate — small, stateless, restartable
- Schema changes require slightly more discipline (renames need aliases, etc.) — a feature, not a bug
