# Schema evolution (Avro + Karapace)

## Compatibility policy

`BACKWARD` (set at registry level in `docker-compose.yml` and K8s ConfigMap).

| Change | Allowed under BACKWARD? |
|---|---|
| Add a field with a default | ✅ |
| Remove a field that had a default | ✅ |
| Rename a field | ❌ (use `aliases` instead) |
| Narrow a type (`long` → `int`) | ❌ |
| Widen a type (`int` → `long`) | ✅ |
| Change a field from required to optional | ✅ |
| Add a new field without a default | ❌ |

## Process for changing a schema

1. Edit the `.avsc` file in `schemas/events/v1/`
2. Run `./scripts/bootstrap.sh` locally — Karapace registers the new version; if incompatible, registration fails
3. Open a PR — CI re-validates against a scratch Karapace, fails the PR if incompatible
4. After merge, the next `release.yml` run picks up the new schema; consumers running the old code keep working (BACKWARD compatibility means the new schema can be read by old consumers if we follow the rules)

## Breaking changes

If you genuinely need a breaking change, create a new topic version (`incidents.v2.avsc`) and dual-write from the producer until all consumers have migrated.

## CI guard

`.github/workflows/ci.yml`'s `contracts` job spins up Karapace, registers each schema, fails if any rejection.
