# C4 Level 1 — System Context

The system in its environment: who interacts with it, what external systems it depends on.

```mermaid
C4Context
    title System Context — EHS Incident System

    Person(worker,        "Worker",        "Reports incidents from their site")
    Person(investigator,  "Investigator",  "Triages, investigates, assigns corrective actions")
    Person(admin,         "Admin",         "Configures the workspace; manages users and sites")

    System(ehs, "EHS Incident System", "Multi-tenant EHS incident reporting and follow-up platform with event-driven notifications")

    System_Ext(smtp,     "SMTP / Email provider", "Delivers notification emails (MailCatcher in dev; SES / SendGrid / Postmark in prod)")
    System_Ext(telegram, "Telegram Bot API",      "Delivers notification messages to opted-in users")
    System_Ext(s3,       "S3-compatible storage", "Stores attachment binaries (MinIO in dev; AWS S3 in prod)")

    Rel(worker,        ehs, "Submits incidents, completes assigned actions", "HTTPS")
    Rel(investigator,  ehs, "Triages, investigates, manages actions",         "HTTPS")
    Rel(admin,         ehs, "Manages org, users, sites, settings",            "HTTPS")

    Rel(ehs, smtp,     "Sends notification emails",      "SMTP")
    Rel(ehs, telegram, "Sends in-app push to Telegram",  "HTTPS")
    Rel(ehs, s3,       "Stores attachment binaries",     "HTTPS / S3 API")
```

## Why this view

A new developer or interviewer should be able to read this single diagram and understand:

1. **The actors.** Three roles, none of them anonymous — even "submit an incident" requires authentication, because every incident must be attributable.
2. **The system boundary.** What's "inside" is one cohesive product; the integrations (Telegram, SMTP, S3) are clearly external.
3. **Why those externals.** Notification fanout is a first-class concern in EHS (incidents must reach people *now*), and attachments — photos, witness statements — quickly outgrow the size that belongs in Postgres.

The L2 (Container) view drills into how the system is decomposed internally.
