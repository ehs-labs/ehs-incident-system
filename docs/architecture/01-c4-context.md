# C4 Level 1 — System Context

The system in its environment: who interacts with it, what external systems it depends on.

```mermaid
%%{init: {'flowchart': {'htmlLabels': true}, 'themeVariables': {'fontSize': '18px'}}}%%
flowchart TB
    %% Actors
    worker["<b>Worker</b><br/><i>[Person]</i><br/>Reports incidents from their site"]
    investigator["<b>Investigator</b><br/><i>[Person]</i><br/>Triages, investigates,<br/>assigns corrective actions"]
    admin["<b>Admin</b><br/><i>[Person]</i><br/>Configures the workspace;<br/>manages users and sites"]

    %% System in scope
    ehs["<b>EHS Incident System</b><br/><i>[Software System]</i><br/>Multi-tenant EHS incident reporting<br/>and follow-up platform with<br/>event-driven notifications"]

    %% External systems
    smtp["<b>SMTP / Email provider</b><br/><i>[External System]</i><br/>Delivers notification emails<br/>(MailCatcher in dev; SES /<br/>SendGrid / Postmark in prod)"]
    telegram["<b>Telegram Bot API</b><br/><i>[External System]</i><br/>Delivers notification messages<br/>to opted-in users"]
    s3["<b>S3-compatible storage</b><br/><i>[External System]</i><br/>Stores attachment binaries<br/>(MinIO in dev; AWS S3 in prod)"]

    %% Relationships
    worker -->|"Submits incidents,<br/>completes assigned actions<br/><i>[HTTPS]</i>"| ehs
    investigator -->|"Triages, investigates,<br/>manages actions<br/><i>[HTTPS]</i>"| ehs
    admin -->|"Manages org, users,<br/>sites, settings<br/><i>[HTTPS]</i>"| ehs

    ehs -->|"Sends notification emails<br/><i>[SMTP]</i>"| smtp
    ehs -->|"Sends in-app push to Telegram<br/><i>[HTTPS]</i>"| telegram
    ehs -->|"Stores attachment binaries<br/><i>[HTTPS / S3 API]</i>"| s3

    %% C4-style classDefs
    classDef person   fill:#08427b,stroke:#052e56,color:#ffffff,stroke-width:1px
    classDef system   fill:#1168bd,stroke:#0b4884,color:#ffffff,stroke-width:1px
    classDef external fill:#999999,stroke:#6b6b6b,color:#ffffff,stroke-width:1px

    class worker,investigator,admin person
    class ehs system
    class smtp,telegram,s3 external
```

## Why this view

A new developer or interviewer should be able to read this single diagram and understand:

1. **The actors.** Three roles, none of them anonymous — even "submit an incident" requires authentication, because every incident must be attributable.
2. **The system boundary.** What's "inside" is one cohesive product; the integrations (Telegram, SMTP, S3) are clearly external.
3. **Why those externals.** Notification fanout is a first-class concern in EHS (incidents must reach people *now*), and attachments — photos, witness statements — quickly outgrow the size that belongs in Postgres.

The L2 (Container) view drills into how the system is decomposed internally.
