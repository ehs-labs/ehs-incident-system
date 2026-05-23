# Corrective Action Transition Notes — Design

**Date:** 2026-05-22
**Status:** Approved (pending spec review)
**Branch:** `feat/corrective-action-flow`

## Problem

Today, transitions on a `CorrectiveAction` (`assign`, `start`, `complete`, `verify`, `cancel`) carry no free-text context. A worker completes an action and there is no field to record *what was done*; an investigator cancels and there is no field for *why*. Notifications fired by these transitions therefore read generically ("Wendy marked it done") rather than carrying the most useful information ("Wendy marked it done — replaced wheel, bearing also looks worn").

## Goal

Let any user performing a transition attach an optional free-text note. Persist the note as an audit-log entry, surface it in the SPA as a chronological activity feed, and include it in the email + in-app notification body when present.

## Scope

In scope:

- Optional note on `create` (in addition to the existing `Description` field — Description is "what to do", note is "context for this assignment").
- Optional note on every transition: `start`, `complete`, `verify`, `cancel`.
- Notification bodies for `assigned`, `completed`, `verified`, `cancelled` include the note when present.
- A new "Activity" tab on the corrective-action detail panel showing the chronological transition history.

Out of scope:

- Editing or deleting past notes (the log is append-only).
- Notifications for `started` (low signal — recipients would be the same investigator who is about to be notified again on `completed`).
- Attaching files to notes (the action already supports `evidence` uploads).
- TTL / retention of audit-log rows.

## Storage

New table `corrective_action_events`, one row per state change:

```
id                     bigserial primary key
corrective_action_id   bigint not null references corrective_actions(id) on delete cascade
event_name             text not null      -- assigned | started | completed | verified | cancelled
actor_id               bigint not null references users(id)
note                   text               -- nullable
created_at             timestamp not null
```

Indexes:

- `(corrective_action_id, created_at)` for the activity-feed query.
- `event_name` on its own is not needed at this scale.

Rationale (see brainstorm Q&A): a dedicated audit table is preferred over per-transition columns on `corrective_actions` (which would lose the actor + timestamp per event and bloat the row) and over reusing PaperTrail versions (which were not designed to carry author commentary).

`outbox_events` stays as the Kafka outbox and is **not** unified with this table. Each transition writes two rows in the same DB transaction: one to `corrective_action_events` (permanent domain audit log, read by the SPA) and one to `outbox_events` (transient Kafka shipping ledger, consumed by the notifier).

## API

### Create action — accept a note

`POST /api/v1/incidents/:incident_id/corrective_actions`

Request body extends the existing shape with an optional `note`:

```json
{
  "corrective_action": {
    "title": "...",
    "description": "...",
    "due_date": "...",
    "assignee_id": 3,
    "note": "Spotted during weekly walkthrough — please prioritize."
  }
}
```

Behavior: the action is created as today; an `assigned` row is written to `corrective_action_events` carrying the `actor_id = current_user.id` and the `note`; the existing `publish_assigned_event!` is extended to carry the note in its payload. If `note` is absent, the event row's `note` is `NULL`.

### Transition — accept a note

`POST /api/v1/corrective_actions/:id/transitions`

Request body:

```json
{ "event": "complete", "note": "Replaced wheel; bearing looks worn." }
```

Behavior: AASM transition runs as today; on success an event row is written and the corresponding Kafka event is emitted. `note` is optional everywhere.

### Activity feed

`GET /api/v1/corrective_actions/:id/events`

Returns the chronological list:

```json
{
  "data": [
    {
      "id": "1",
      "type": "corrective_action_event",
      "attributes": {
        "event_name": "assigned",
        "note": "Spotted during weekly walkthrough...",
        "actor_id": 2,
        "created_at": "2026-05-22T15:17:50Z"
      }
    },
    { "...": "..." }
  ]
}
```

Visibility: anyone who can `show` the parent action via `CorrectiveActionPolicy` can list its events. A new `CorrectiveActionEventPolicy::Scope` filters by parent visibility.

## Model layer

```ruby
class CorrectiveActionEvent < ApplicationRecord
  EVENT_NAMES = %w[assigned started completed verified cancelled].freeze

  belongs_to :corrective_action
  belongs_to :actor, class_name: "User"

  validates :event_name, inclusion: { in: EVENT_NAMES }
  validates :note, length: { maximum: 2000 }, allow_nil: true
end
```

`CorrectiveAction` gains:

- `has_many :events, class_name: "CorrectiveActionEvent", dependent: :destroy`
- A thread-local `pending_note` setter (`attr_accessor :pending_note`) set by the controller before calling the AASM event method, read inside the `after` callback.

Each AASM event's `after` block is extended to log a row and pass the note through to the Kafka event:

```ruby
event :complete do
  transitions from: :in_progress, to: :done
  after do
    update_column(:completed_at, Time.current)
    log = events.create!(
      event_name: :completed,
      actor_id: Current.user.id,
      note: pending_note
    )
    publish_event!(
      "CorrectiveActionCompleted",
      recipient_user_ids: completion_recipient_ids,
      note: log.note
    )
  end
end
```

The same shape applies to `start`, `verify`, `cancel`. The `assigned` row is written from the controller (not from AASM, since assignment is implicit on create) in the same transaction as `save!`.

`publish_event!` is extended to accept an optional `note:` keyword, which `event_subject_for` includes in the subject for every event type. The `note` field is nullable in every Avro schema.

## Event / notifier changes

New Avro schemas added under `schemas/events/v1/`:

- `CorrectiveActionStarted.avsc` — emitted but **not fanned out** by the notifier (no handler registered). Reserved for future SLA or telemetry consumers.
- `CorrectiveActionVerified.avsc` — fanned out to the action's `assignee_id` (worker who completed it gets confirmation that their work was signed off).
- `CorrectiveActionCancelled.avsc` — fanned out to the assignee.

All existing schemas (`CorrectiveActionAssigned`, `CorrectiveActionCompleted`, `CorrectiveActionOverdue`) gain a nullable `note` field at the top level of the `subject`. Default: `null`. Avro union type `["null", "string"]` with default `null` to preserve backward compatibility for replayed messages.

Notifier handler bodies are extended to interpolate the note when present:

> *"Wendy Worker marked corrective action "Replace the worn pallet jack wheel" on incident #39 as done. Note: Replaced wheel, bearing also looks worn."*

When the note is absent or blank, the body falls back to today's wording. The interpolation lives in a small helper so the conditional is not duplicated across handlers.

## Frontend changes

### IncidentDetail.vue — corrective-action panel

1. **New-action form:** add a textarea labelled "Note for assignee (optional)" between `Description` and `Due date`. The submit sends `note` alongside the existing payload.

2. **Transition buttons (Start / Complete / Send for verification / Cancel):** each opens a small Naive UI dialog (`NModal` + `NInput type="textarea"`) with a single optional note field and a Confirm button. Confirming POSTs to `/transitions` with `{ event, note }`. The dialog stays cancellable.

3. **Activity tab:** a new tab on the action's expandable row showing the chronological event list with actor name (resolved from existing `findIncluded` helper or `orgUsers`), human-readable event name, timestamp, and the note (rendered with simple line-break preservation).

### API client

`frontend/src/api/incidents.ts` (or `actions.ts`):

- `createIncidentAction(incidentId, payload)` already exists — extend its `payload` type to include `note?: string`.
- `transitionAction(actionId, payload)` — extend payload to `{ event: ActionTransition, note?: string }`.
- New `listActionEvents(actionId)` returning the JSON:API list.

## Testing

### Core-api

- **Model spec:** transitioning with a note writes a `CorrectiveActionEvent` row with the right actor; transitioning without a note writes a row with `note: nil`; rejecting a 2001-character note.
- **Outbox spec:** each transition publishes a Kafka event whose `subject.note` field equals the event row's note (or is `null`).
- **Request spec:**
  - `POST /corrective_actions/:id/transitions` with `note` persists it.
  - `GET /corrective_actions/:id/events` returns the chronological list, scoped to viewers of the parent action.
  - Authorization: a worker not on the action and not in the same org gets 403 on the events list.

### Notifier

- Handler renders the note when present, falls back without it.
- `CorrectiveActionVerified` and `CorrectiveActionCancelled` consumer tests added (mirroring the existing `CorrectiveActionAssigned`/`Completed` tests).

### Frontend

- `vue-tsc` + `eslint --max-warnings 0` clean.
- Smoke-test via curl (Pat creates → Wendy completes with note → Pat receives email body that includes the note).

## Migration

Single migration adding `corrective_action_events` plus the composite index. No backfill — historical actions simply have no event rows; the activity tab renders an empty state until further transitions happen.

The Avro schema change is additive (new optional field with `null` default), so already-shipped events on the topic remain consumable.

## Risks and tradeoffs

- **Extra write per transition.** One additional row per state change. Negligible at portfolio scale.
- **Frontend complexity.** Each transition button now opens a dialog instead of firing immediately. Worth it for the UX gain; the dialog can be dismissed with a single Enter key.
- **Backward compatibility.** Old messages on `corrective_actions.v1` without a `note` field still decode because the Avro union type defaults to `null`.

## Open questions

None — all scope decisions resolved in the brainstorming pass:

- Notes on every transition + create (confirmed by user).
- Notes included in notification bodies (confirmed by user).
- TTL not in scope for this change (confirmed by user).
