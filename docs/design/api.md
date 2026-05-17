# REST API overview

## Conventions

- **Base path:** `/api/v1`
- **Auth:** `Authorization: Bearer <jwt>` on every request (except `/auth/login`, `/auth/signup`, `/healthz`)
- **Response:** JSON; `application/json`
- **Errors:** RFC 7807 `application/problem+json`:
  ```json
  {
    "type":  "about:blank",
    "title": "Validation failed",
    "status": 422,
    "errors": [
      { "pointer": "/data/attributes/severity", "detail": "must be 1-5" }
    ]
  }
  ```
- **Pagination:** RFC 5988 `Link` headers (`first`, `prev`, `next`, `last`) and `X-Total-Count`

## Source of truth

The full schema is emitted by `rswag` from RSpec request specs and committed as
[`core-api/openapi.yaml`](../../core-api/openapi.yaml). The frontend regenerates
its TypeScript types from this file via `pnpm gen:api`.

Local Swagger UI: `http://localhost:3000/api-docs`.

## Endpoint groups (summary)

| Group | Routes |
|---|---|
| Auth | `POST /auth/{login,signup,refresh,password}`, `DELETE /auth/logout`, `GET /auth/confirm` |
| Profile | `GET /me`, `PATCH /me`, `PATCH /me/password`, `POST /me/link_telegram` |
| Sites | `GET/POST /sites`, `GET/PATCH/DELETE /sites/:id` |
| Incidents | `GET/POST /incidents`, `GET/PATCH /incidents/:id`, `POST /incidents/:id/transitions` |
| Incident sub-resources | `/incidents/:id/{attachments,comments,corrective_actions}` |
| Corrective actions | `GET/PATCH /corrective_actions/:id`, `POST /corrective_actions/:id/transitions` |
| Notifications | `GET /notifications`, `PATCH /notifications/:id`, `POST /notifications/mark_all_read` |
| Dashboard | `GET /dashboard` |
| Admin | `/admin/users`, `/admin/sites`, `/admin/settings` |
| Internal (service-to-service) | `GET /internal/users/:id/notification_addresses` |

## State transitions

State changes are POSTs to a transitions endpoint:

```http
POST /api/v1/incidents/01HXY.../transitions
Authorization: Bearer ...
Content-Type: application/json

{ "event": "triage", "assignee_id": "01HXY...", "severity": 2, "note": "..." }
```

The server validates the AASM guard and returns `200 OK` with the updated resource, or `422` with a problem-json describing the violated guard.
