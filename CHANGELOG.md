# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Corrective actions: optional free-text note on create and every state transition (start / complete / verify / cancel). Notes are interpolated into the email + in-app notification body and appear in a new chronological Activity feed on the action detail panel.
- New endpoint `GET /api/v1/corrective_actions/:id/events` returning the action's append-only audit log.
- New endpoint `GET /api/v1/assignable_users` exposing org users to admins and investigators (populates assignee pickers; the existing `/admin/users` endpoint stays admin-only).
- New Avro event types `CorrectiveActionStarted`, `CorrectiveActionVerified`, `CorrectiveActionCancelled`. All five `corrective_actions.v1` event subjects gain a nullable `note` field (backward-compatible).
- Investigators now receive a notification when an assignee marks a corrective action as done — including the worker's optional completion note.

### Changed
- `EventBus#publish!` no longer compacts the subject hash; nullable fields are emitted explicitly as `null` so consumers see them.
- Test environment uses ActiveJob's `:test` queue adapter so specs run from the host without Redis.

- Initial project scaffold: monorepo structure, git/CI foundation, docker-compose, K8s Kustomize base
- `core-api` (Rails 7.2 API-only) skeleton — Devise+JWT auth, AASM state machines, PaperTrail audit, Sidekiq, rdkafka producer
- `notifier` (Sinatra) skeleton — Karafka consumers, Falcon WebSocket server, channel adapters (email, Telegram, in-app)
- `frontend` (Vue 3 + TypeScript + Vite) skeleton — Pinia, Vue Router, Naive UI, Axios
- `shared/envelope` — AES-256-GCM field-level encryption gem
- Avro event schemas in `schemas/events/v1/`, registered with Karapace
- Documentation: C4 diagrams (L1–L3), ER & state diagrams, sequence diagrams, ADRs, operations runbooks
