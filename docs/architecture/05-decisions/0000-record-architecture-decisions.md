# ADR-0000: We use ADRs

- **Status:** Accepted
- **Date:** 2026-05-17

## Context

Architectural decisions made now (event-driven, two services, Avro, etc.) will
be questioned six months from now — "why did we do X?" Without a written
record, future contributors (or future-you) re-litigate every choice.

## Decision

We capture each non-trivial architectural decision as a one-page ADR in
`docs/architecture/05-decisions/` using the Nygard format:

- **Title** — what was decided
- **Status** — Proposed / Accepted / Superseded (with link to the superseder)
- **Context** — what was happening that made us face this choice
- **Decision** — what we chose
- **Consequences** — what we gain, what we give up, and what changes elsewhere

ADRs are numbered (`NNNN-kebab-title.md`) and immutable once Accepted; if we change our mind, we add a new ADR that supersedes the old one.

## Consequences

- New contributors can read the ADR log to understand the system's *intent*, not just its current code
- Code review can refer to ADRs by number ("this contradicts ADR-0003")
- Slight overhead — every meaningful decision deserves a 10-minute write-up
