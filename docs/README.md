# Documentation map

GitHub renders Mermaid in Markdown — every diagram below is viewable on the repo page without cloning.

## Architecture

- [01 — C4 L1 System Context](architecture/01-c4-context.md)
- [02 — C4 L2 Containers](architecture/02-c4-container.md)
- [03 — C4 L3 Notifier component deep-dive](architecture/03-c4-component-notifier.md)
- [04 — Deployment topology (Kubernetes)](architecture/04-deployment.md)
- [Architecture Decision Records (ADRs)](architecture/05-decisions/)

## Design

- [Domain model (ER)](design/domain-model.md)
- [State machines](design/state-machines.md)
- [Event contract](design/event-contract.md)
- [Security](design/security.md)
- [REST API overview](design/api.md)
- [WebSocket protocol](design/websocket.md)

## Sequence flows

- [Incident submission](flows/incident-submission.md)
- [Triage and assign](flows/incident-triage-and-assign.md)
- [Notification fanout](flows/notification-fanout.md)
- [Auth + JWT refresh](flows/auth-and-jwt-refresh.md)
- [SLA breach](flows/sla-breach.md)
- [Field-cipher key rotation](flows/key-rotation.md)

## Use cases

- [Personas](use-cases/personas.md)
- [Use case map](use-cases/use-cases.md)

## Operations

- [Local development](operations/local-development.md)
- [Docker Compose details](operations/docker-compose.md)
- [Kubernetes deploy](operations/kubernetes.md)
- [Migrations + tripwire](operations/migrations.md)
- [Backup & restore](operations/backup-restore.md)
- [Key rotation](operations/key-rotation.md)
- [Schema evolution](operations/schema-evolution.md)
- [Observability](operations/observability.md)
- [End-to-end verification](operations/end-to-end-verification.md)
- [Troubleshooting](operations/troubleshooting.md)

## User guides

- [Worker guide](user-guide/worker-guide.md)
- [Investigator guide](user-guide/investigator-guide.md)
- [Admin guide](user-guide/admin-guide.md)
