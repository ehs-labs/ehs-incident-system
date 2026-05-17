# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial project scaffold: monorepo structure, git/CI foundation, docker-compose, K8s Kustomize base
- `core-api` (Rails 7.2 API-only) skeleton — Devise+JWT auth, AASM state machines, PaperTrail audit, Sidekiq, rdkafka producer
- `notifier` (Sinatra) skeleton — Karafka consumers, Falcon WebSocket server, channel adapters (email, Telegram, in-app)
- `frontend` (Vue 3 + TypeScript + Vite) skeleton — Pinia, Vue Router, Naive UI, Axios
- `shared/envelope` — AES-256-GCM field-level encryption gem
- Avro event schemas in `schemas/events/v1/`, registered with Karapace
- Documentation: C4 diagrams (L1–L3), ER & state diagrams, sequence diagrams, ADRs, operations runbooks
