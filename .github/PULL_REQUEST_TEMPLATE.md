<!--
Thanks for the PR!

Title: use Conventional Commits — `feat: ...`, `fix: ...`, `chore: ...`, `docs: ...`, `refactor: ...`, `test: ...`.
Keep titles under 70 chars; use the body for detail.
-->

## Summary

<!-- 1-3 sentences. What does this PR do and why? -->

## Linked issue

Closes #

## Test plan

<!-- How did you verify this works? Be specific. -->
- [ ] Unit tests added/updated
- [ ] Integration / request specs added/updated
- [ ] Manual verification: <describe>
- [ ] CI is green

## Screenshots / recordings

<!-- For UI changes; delete this section otherwise. -->

## Breaking changes

<!-- Migrations? Event schema changes? Public API changes? Document them here. -->
- [ ] None
- [ ] Yes — described above

## Checklist

- [ ] Self-reviewed the diff
- [ ] No secrets, credentials, or PII committed
- [ ] Updated docs if behavior changed (`README.md`, `docs/**`, ADR if architectural)
- [ ] Updated `CHANGELOG.md` under `## [Unreleased]`
- [ ] Migration scripts are reversible (`down` method or fully reversible `change`)
- [ ] Avro schema changes are backward-compatible (Karapace will reject otherwise)
