# Corrective Action Transition Notes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let any user attach an optional free-text note to corrective-action transitions (create, start, complete, verify, cancel). Persist notes in a new audit table, include them in notification bodies, and surface them as a chronological "Activity" feed in the SPA.

**Architecture:** A new `corrective_action_events` table records one row per state change (event_name, actor, note, timestamp). AASM `after` callbacks write to it in the same DB transaction as the existing outbox emission. The note is carried through the Avro payload so the notifier can interpolate it into the email/in-app body without re-querying the audit log. The SPA gains a transition modal that collects the optional note and an Activity tab that renders the events list.

**Tech Stack:** Rails 8.1 / RSpec / Pundit / AASM / Sequel (notifier) / Karafka + Avro / Vue 3 + Naive UI + Pinia.

**Spec:** [2026-05-22-corrective-action-transition-notes-design.md](../specs/2026-05-22-corrective-action-transition-notes-design.md)

---

## Test-running convention

All `rspec` commands assume you are running from the host. The project tests need `POSTGRES_HOST=127.0.0.1` (Postgres is in docker, only reachable on the IPv4 loopback from the host) and the repo `.env` loaded for `JWT_SECRET` etc. To avoid repeating the boilerplate, export this once per shell:

```bash
cd /Users/stitch80/Development/RubyPortfolio/ehs-incident-system/core-api
set -a && source ../.env && set +a
export POSTGRES_HOST=127.0.0.1 RAILS_ENV=test
```

Notifier:

```bash
cd /Users/stitch80/Development/RubyPortfolio/ehs-incident-system/notifier
export DATABASE_URL=postgres://ehs:devpassword@127.0.0.1:5432/ehs_notifier_test
```

Each task ends with a commit. Use the existing commit-message style (`feat(scope): subject`).

---

## Task 1: Create `corrective_action_events` table and model

**Files:**

- Create: `core-api/db/migrate/<timestamp>_create_corrective_action_events.rb`
- Create: `core-api/app/models/corrective_action_event.rb`
- Create: `core-api/spec/factories/corrective_action_events.rb`
- Create: `core-api/spec/models/corrective_action_event_spec.rb`

### Steps

- [ ] **Step 1: Generate the migration**

```bash
bundle exec rails g migration CreateCorrectiveActionEvents
```

Open the generated file and replace its body with:

```ruby
class CreateCorrectiveActionEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :corrective_action_events do |t|
      t.references :corrective_action, null: false, foreign_key: { on_delete: :cascade }
      t.string     :event_name, null: false
      t.references :actor,      null: false, foreign_key: { to_table: :users }
      t.text       :note
      t.datetime   :created_at, null: false
    end

    add_index :corrective_action_events, [:corrective_action_id, :created_at],
              name: "idx_ca_events_by_action_created"
  end
end
```

Notes for the implementer:

- Only `created_at` — no `updated_at`. Audit rows are immutable.
- `actor_id` references `users.id` (matches the `belongs_to :actor` association below).
- The composite index supports the activity-feed query (`WHERE corrective_action_id = ? ORDER BY created_at`).

- [ ] **Step 2: Run the migration**

```bash
bundle exec rails db:migrate
```

Expected: a single `CreateCorrectiveActionEvents` migration line, no errors.

- [ ] **Step 3: Write the model**

Create `core-api/app/models/corrective_action_event.rb`:

```ruby
class CorrectiveActionEvent < ApplicationRecord
  EVENT_NAMES = %w[assigned started completed verified cancelled].freeze

  belongs_to :corrective_action
  belongs_to :actor, class_name: "User"

  validates :event_name, inclusion: { in: EVENT_NAMES }
  validates :note, length: { maximum: 2000 }, allow_nil: true
end
```

- [ ] **Step 4: Add a factory**

Create `core-api/spec/factories/corrective_action_events.rb`:

```ruby
FactoryBot.define do
  factory :corrective_action_event do
    corrective_action
    actor { association(:user, organization: corrective_action.incident.organization) }
    event_name { "assigned" }
    note { nil }
  end
end
```

- [ ] **Step 5: Write the model spec**

Create `core-api/spec/models/corrective_action_event_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe CorrectiveActionEvent, type: :model do
  describe "validations" do
    it "accepts each documented event name" do
      CorrectiveActionEvent::EVENT_NAMES.each do |name|
        evt = build(:corrective_action_event, event_name: name)
        expect(evt).to be_valid, "expected #{name.inspect} to be a valid event name"
      end
    end

    it "rejects an unknown event name" do
      evt = build(:corrective_action_event, event_name: "exploded")
      expect(evt).not_to be_valid
      expect(evt.errors[:event_name]).to include(/is not included/)
    end

    it "rejects a note longer than 2000 characters" do
      evt = build(:corrective_action_event, note: "x" * 2001)
      expect(evt).not_to be_valid
    end

    it "accepts a nil note" do
      evt = build(:corrective_action_event, note: nil)
      expect(evt).to be_valid
    end
  end

  describe "cascade on parent delete" do
    it "is destroyed when its corrective_action is destroyed" do
      action = create(:corrective_action)
      evt    = create(:corrective_action_event, corrective_action: action)

      action.destroy!
      expect(CorrectiveActionEvent.where(id: evt.id)).to be_empty
    end
  end
end
```

- [ ] **Step 6: Run the spec**

```bash
bundle exec rspec spec/models/corrective_action_event_spec.rb
```

Expected: `6 examples, 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add core-api/db/migrate core-api/app/models/corrective_action_event.rb \
        core-api/spec/factories/corrective_action_events.rb \
        core-api/spec/models/corrective_action_event_spec.rb
git commit -m "feat(corrective-actions): add corrective_action_events audit table"
```

---

## Task 2: Wire AASM transitions to write event rows and carry notes

This task extends `CorrectiveAction` so every transition writes an audit row and passes the note through to the Kafka payload.

**Files:**

- Modify: `core-api/app/models/corrective_action.rb`
- Modify: `core-api/spec/models/corrective_action_spec.rb`

### Steps

- [ ] **Step 1: Write the failing model specs**

Append to `core-api/spec/models/corrective_action_spec.rb` inside `describe "event publishing"`:

```ruby
    it "logs a CorrectiveActionEvent row on every transition with the right actor and note" do
      incident.update_column(:assignee_id, investigator.id)

      Current.user = investigator
      action.pending_note = "Begin today after parts arrive"
      action.start!

      Current.user = assignee
      action.pending_note = "Replaced wheel, bearing looks worn"
      action.complete!

      Current.user = investigator
      action.pending_note = "Confirmed; signing off"
      action.verify!

      events = action.events.order(:created_at)
      expect(events.map(&:event_name)).to eq(%w[started completed verified])
      expect(events.map(&:actor_id)).to eq([investigator.id, assignee.id, investigator.id])
      expect(events.map(&:note)).to eq([
        "Begin today after parts arrive",
        "Replaced wheel, bearing looks worn",
        "Confirmed; signing off"
      ])
    ensure
      Current.user = nil
    end

    it "writes a nil-note event row when no pending_note is set" do
      Current.user = assignee
      action.start!
      action.complete!

      expect(action.events.last.note).to be_nil
    ensure
      Current.user = nil
    end

    it "includes the note in the CorrectiveActionCompleted outbox payload" do
      incident.update_column(:assignee_id, investigator.id)
      Current.user = assignee
      action.start!
      action.pending_note = "Replaced wheel"
      action.complete!

      event = OutboxEvent.where(event_type: "CorrectiveActionCompleted").order(:id).last
      expect(event.payload["subject"]["note"]).to eq("Replaced wheel")
    ensure
      Current.user = nil
    end
```

Run the spec to confirm it fails (no `pending_note` accessor yet, no `events` association, no `note` in subject):

```bash
bundle exec rspec spec/models/corrective_action_spec.rb -e "logs a CorrectiveActionEvent"
```

Expected: failures referencing `pending_note=` or `events`.

- [ ] **Step 2: Extend the model**

Open `core-api/app/models/corrective_action.rb`. Make these changes (preserve everything not shown):

After the existing `has_many_attached :evidence` line, add:

```ruby
  has_many :events, class_name: "CorrectiveActionEvent", dependent: :destroy

  # Set by the controller before invoking an AASM event method. Read inside
  # AASM after-callbacks; we don't pass arguments through aasm event! methods.
  attr_accessor :pending_note
```

Replace the AASM block (`event :start`, `event :complete`, `event :verify`, `event :cancel`) with:

```ruby
    event :start do
      transitions from: :open, to: :in_progress
      after { log_transition!(:started) }
    end

    event :complete do
      transitions from: :in_progress, to: :done
      after do
        update_column(:completed_at, Time.current)
        log = log_transition!(:completed)
        publish_event!(
          "CorrectiveActionCompleted",
          recipient_user_ids: completion_recipient_ids,
          note: log.note
        )
      end
    end

    event :verify do
      transitions from: :done, to: :verified
      after do
        update_column(:verified_at, Time.current)
        log = log_transition!(:verified)
        publish_event!(
          "CorrectiveActionVerified",
          recipient_user_ids: [ assignee_id ].compact,
          note: log.note
        )
        maybe_close_parent_incident!
      end
    end

    event :cancel do
      transitions from: %i[open in_progress done], to: :cancelled
      after do
        log = log_transition!(:cancelled)
        publish_event!(
          "CorrectiveActionCancelled",
          recipient_user_ids: [ assignee_id ].compact,
          note: log.note
        )
      end
    end
```

In the existing `publish_assigned_event!` method, pass the note through:

```ruby
  def publish_assigned_event!
    publish_event!(
      "CorrectiveActionAssigned",
      recipient_user_ids: [ assignee_id ].compact,
      note: events.where(event_name: "assigned").order(:created_at).last&.note
    )
  end
```

In the `private` section, change `publish_event!` to accept `note:`:

```ruby
  def publish_event!(event_type, recipient_user_ids:, note: nil, actor_id_override: nil)
    EventBus.publish!(
      event_type:        event_type,
      topic:             "corrective_actions.v1",
      partition_key:     organization_id.to_s,
      org_id:            organization_id,
      actor_id:          actor_id_override || (Current.user&.id || created_by_id),
      subject:           event_subject_for(event_type, note: note),
      recipient_user_ids: recipient_user_ids
    )
  end
```

Replace `event_subject_for(event_type)` with a `note:`-aware version:

```ruby
  def event_subject_for(event_type, note: nil)
    base =
      case event_type
      when "CorrectiveActionAssigned"
        {
          action_id:   id.to_s,
          incident_id: incident_id.to_s,
          assignee_id: assignee_id.to_s,
          title:       title,
          due_date:    due_date.to_date
        }
      when "CorrectiveActionOverdue"
        {
          action_id:    id.to_s,
          incident_id:  incident_id.to_s,
          assignee_id:  assignee_id.to_s,
          due_date:     due_date.to_date,
          days_overdue: ((Time.current.to_date - due_date.to_date).to_i)
        }
      when "CorrectiveActionCompleted"
        {
          action_id:    id.to_s,
          incident_id:  incident_id.to_s,
          assignee_id:  assignee_id.to_s,
          title:        title,
          completed_at: completed_at || Time.current
        }
      when "CorrectiveActionStarted", "CorrectiveActionVerified", "CorrectiveActionCancelled"
        {
          action_id:   id.to_s,
          incident_id: incident_id.to_s,
          assignee_id: assignee_id.to_s,
          title:       title
        }
      else
        { action_id: id.to_s }
      end

    base.merge(note: note)
  end
```

Add the new `log_transition!` and existing `completion_recipient_ids` (already present) — keep `completion_recipient_ids` as-is, and add:

```ruby
  def log_transition!(event_name)
    events.create!(
      event_name: event_name.to_s,
      actor_id:   Current.user.id,
      note:       pending_note
    ).tap { self.pending_note = nil }
  end
```

- [ ] **Step 3: Run the model spec**

```bash
bundle exec rspec spec/models/corrective_action_spec.rb
```

Expected: all model specs pass (existing + the three new ones). If the existing `CorrectiveActionCompleted` outbox spec fails because its `subject.keys` matcher is now too strict (it now also contains `note`), update it to expect the `note` key:

```ruby
expect(subject.keys).to match_array(%w[action_id incident_id assignee_id title completed_at note])
```

Similarly check the assigned-event subject test (now also includes `note`):

```ruby
expect(subject.keys).to match_array(%w[action_id incident_id assignee_id title due_date note])
```

- [ ] **Step 4: Commit**

```bash
git add core-api/app/models/corrective_action.rb core-api/spec/models/corrective_action_spec.rb
git commit -m "feat(corrective-actions): log every transition and carry note in events"
```

---

## Task 3: Controller — accept `note` on create and transitions

**Files:**

- Modify: `core-api/app/controllers/api/v1/corrective_actions_controller.rb`
- Modify: `core-api/spec/requests/corrective_actions_spec.rb`

### Steps

- [ ] **Step 1: Add failing request specs**

Append the following inside the existing top-level `RSpec.describe "Corrective Actions API"` block in `core-api/spec/requests/corrective_actions_spec.rb` (find where the existing `post` block for create lives and add):

```ruby
      response "201", "Created — accepts optional note that becomes the assigned event" do
        let(:body) do
          {
            corrective_action: {
              title: "Fix valve",
              description: "Replace the valve before Friday.",
              due_date: 5.days.from_now.iso8601,
              assignee_id: assignee.id,
              note: "Found during walkthrough; please prioritize."
            }
          }
        end

        run_test! do |response|
          action_id = JSON.parse(response.body)["data"]["id"].to_i
          evt = CorrectiveActionEvent.where(corrective_action_id: action_id, event_name: "assigned").first
          expect(evt).to be_present
          expect(evt.note).to eq("Found during walkthrough; please prioritize.")
          expect(evt.actor_id).to eq(investigator.id)
        end
      end
```

And for transitions, add inside the existing transitions path block:

```ruby
      response "200", "OK — note is attached to the event and propagated to the outbox payload" do
        let(:body) { { event: "start", note: "Beginning today" } }

        before do
          action.update_column(:state, "open")
        end

        run_test! do |response|
          evt = action.reload.events.order(:created_at).last
          expect(evt.event_name).to eq("started")
          expect(evt.note).to eq("Beginning today")
        end
      end
```

(Adjust the `before`/`let` blocks to match the existing factory + auth setup in that file — read it first and follow its conventions; the names above assume `action`, `investigator`, `assignee` lets are already defined.)

Run the new specs and confirm they fail:

```bash
bundle exec rspec spec/requests/corrective_actions_spec.rb
```

Expected: failures because `note` isn't permitted yet and the controller doesn't write the assigned-event row.

- [ ] **Step 2: Update `corrective_actions_controller.rb`**

Replace `corrective_action_params` to permit `note`:

```ruby
      def corrective_action_params
        params.require(:corrective_action).permit(
          :title, :description, :due_date, :assignee_id, :note, evidence: []
        )
      end
```

Replace `create` so it strips `note` from the model attrs (the model doesn't have a `note` column — the note becomes the assigned event row), writes the assigned event in the same transaction, and then publishes:

```ruby
      def create
        attrs = corrective_action_params
        note  = attrs.delete(:note)

        @action = CorrectiveAction.new(attrs.merge(
          incident_id:   @incident.id,
          created_by_id: current_user.id
        ))
        authorize @action

        ApplicationRecord.transaction do
          @action.save!
          @action.events.create!(
            event_name: "assigned",
            actor_id:   current_user.id,
            note:       note
          )
          @action.publish_assigned_event!
        end

        render json: CorrectiveActionSerializer.new(@action).serializable_hash, status: :created
      end
```

Replace `transition` so it accepts and forwards `note`:

```ruby
      def transition
        event = params[:event].to_s
        unless CorrectiveAction.aasm.events.map { |e| e.name.to_s }.include?(event)
          return render_problem(422, "Unknown event", "Event '#{event}' is not defined on CorrectiveAction")
        end

        authorize @action, "#{event}?"

        ApplicationRecord.transaction do
          @action.pending_note = params[:note].presence
          @action.send("#{event}!")
        end

        render json: CorrectiveActionSerializer.new(@action.reload).serializable_hash
      end
```

- [ ] **Step 3: Run the request specs**

```bash
bundle exec rspec spec/requests/corrective_actions_spec.rb
```

Expected: all specs pass (existing + the two new ones).

- [ ] **Step 4: Commit**

```bash
git add core-api/app/controllers/api/v1/corrective_actions_controller.rb core-api/spec/requests/corrective_actions_spec.rb
git commit -m "feat(corrective-actions): accept note on create and transitions"
```

---

## Task 4: Activity-feed endpoint

**Files:**

- Create: `core-api/app/controllers/api/v1/corrective_action_events_controller.rb`
- Create: `core-api/app/serializers/corrective_action_event_serializer.rb`
- Create: `core-api/app/policies/corrective_action_event_policy.rb`
- Modify: `core-api/config/routes.rb`
- Create: `core-api/spec/requests/corrective_action_events_spec.rb`

### Steps

- [ ] **Step 1: Write the failing request spec**

Create `core-api/spec/requests/corrective_action_events_spec.rb`:

```ruby
require "swagger_helper"

RSpec.describe "Corrective Action Events API", type: :request do
  let(:organization) { create(:organization) }
  let(:site)         { create(:site, organization: organization) }
  let(:reporter)     { create(:user, organization: organization) }
  let(:investigator) { create(:user, :investigator, organization: organization) }
  let(:assignee)     { create(:user, organization: organization) }
  let(:incident)     { create(:incident, organization: organization, site: site, reporter: reporter, assignee: investigator) }
  let(:action)       { create(:corrective_action, incident: incident, assignee: assignee, created_by: investigator) }

  before do
    create(:site_membership, site: site, user: investigator)
    create(:corrective_action_event, corrective_action: action, actor: investigator, event_name: "assigned", note: "Walkthrough finding")
    create(:corrective_action_event, corrective_action: action, actor: assignee, event_name: "started", note: nil)
    create(:corrective_action_event, corrective_action: action, actor: assignee, event_name: "completed", note: "Replaced wheel")
  end

  def jwt_for(u)
    Warden::JWTAuth::UserEncoder.new.call(u, :user, nil).first
  end

  path "/api/v1/corrective_actions/{action_id}/events" do
    parameter name: :action_id, in: :path, schema: { type: :integer }, required: true

    get "List events for a corrective action" do
      tags "corrective_actions"
      produces "application/json"
      security [ { bearerAuth: [] } ]

      let(:action_id)     { action.id }
      let(:Authorization) { "Bearer #{jwt_for(investigator)}" }

      response "200", "OK — chronological list, oldest first" do
        run_test! do |response|
          data = JSON.parse(response.body)["data"]
          expect(data.map { |r| r["attributes"]["event_name"] }).to eq(%w[assigned started completed])
          expect(data.first["attributes"].keys).to match_array(%w[event_name note actor_id created_at])
        end
      end

      response "403", "Forbidden — user from another org" do
        let(:other_org)     { create(:organization) }
        let(:outsider)      { create(:user, :admin, organization: other_org) }
        let(:Authorization) { "Bearer #{jwt_for(outsider)}" }
        produces "application/problem+json"

        run_test! do |response|
          expect(response.status).to eq(403)
        end
      end

      response "404", "Not Found — action does not exist" do
        let(:action_id) { 0 }
        produces "application/problem+json"

        run_test! do |response|
          expect(response.status).to eq(404)
        end
      end
    end
  end
end
```

Run it and confirm route/controller failures:

```bash
bundle exec rspec spec/requests/corrective_action_events_spec.rb
```

Expected: routing error or NoMethodError — that's fine; we are about to create the endpoint.

- [ ] **Step 2: Add the route**

In `core-api/config/routes.rb`, find the nested resources under `resources :corrective_actions, only: %i[index show update] do` (the flat route — around line 62) and add a nested events resource:

```ruby
      resources :corrective_actions, only: %i[index show update] do
        member { post "transitions", to: "corrective_actions#transition" }
        resources :versions, only: :index, controller: "corrective_action_versions"
        resources :events,   only: :index, controller: "corrective_action_events"
      end
```

- [ ] **Step 3: Add the policy**

Create `core-api/app/policies/corrective_action_event_policy.rb`:

```ruby
class CorrectiveActionEventPolicy < ApplicationPolicy
  def index? = parent_visible?

  class Scope < ApplicationPolicy::Scope
    # Expects scope.where(corrective_action_id: id) to have already been narrowed
    # by the controller; we add an org guard here.
    def resolve
      scope.joins(corrective_action: :incident)
           .where(incidents: { organization_id: user.organization_id })
    end
  end

  private

  def parent_visible?
    CorrectiveActionPolicy.new(user, record).show?
  end
end
```

- [ ] **Step 4: Add the serializer**

Create `core-api/app/serializers/corrective_action_event_serializer.rb`:

```ruby
class CorrectiveActionEventSerializer
  include JSONAPI::Serializer

  set_type :corrective_action_event
  attributes :event_name, :note, :actor_id, :created_at
end
```

- [ ] **Step 5: Add the controller**

Create `core-api/app/controllers/api/v1/corrective_action_events_controller.rb`:

```ruby
module Api
  module V1
    class CorrectiveActionEventsController < BaseController
      def index
        action = policy_scope(CorrectiveAction).find(params[:corrective_action_id])
        authorize action, :show?, policy_class: CorrectiveActionEventPolicy

        events = action.events.order(:created_at)
        render json: CorrectiveActionEventSerializer.new(events.to_a).serializable_hash
      end
    end
  end
end
```

- [ ] **Step 6: Run the request spec**

```bash
bundle exec rspec spec/requests/corrective_action_events_spec.rb
```

Expected: `3 examples, 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add core-api/app/controllers/api/v1/corrective_action_events_controller.rb \
        core-api/app/serializers/corrective_action_event_serializer.rb \
        core-api/app/policies/corrective_action_event_policy.rb \
        core-api/config/routes.rb \
        core-api/spec/requests/corrective_action_events_spec.rb
git commit -m "feat(corrective-actions): expose activity-feed endpoint"
```

---

## Task 5: Avro schemas — add `note` and missing event types

**Files:**

- Modify: `schemas/events/v1/CorrectiveActionAssigned.avsc`
- Modify: `schemas/events/v1/CorrectiveActionCompleted.avsc`
- Modify: `schemas/events/v1/CorrectiveActionOverdue.avsc`
- Create: `schemas/events/v1/CorrectiveActionStarted.avsc`
- Create: `schemas/events/v1/CorrectiveActionVerified.avsc`
- Create: `schemas/events/v1/CorrectiveActionCancelled.avsc`

### Steps

- [ ] **Step 1: Add a nullable `note` field to the three existing schemas**

For each of `CorrectiveActionAssigned.avsc`, `CorrectiveActionCompleted.avsc`, and `CorrectiveActionOverdue.avsc`, inside the inner `*Subject` record's `fields` array, append:

```json
,
{
  "name": "note",
  "type": ["null", "string"],
  "default": null
}
```

(Preserve the trailing-comma JSON structure of the existing file.)

This is backward-compatible: replay-encoded events without `note` decode to `nil`.

- [ ] **Step 2: Create the three new schemas**

`schemas/events/v1/CorrectiveActionStarted.avsc`:

```json
{
  "type": "record",
  "name": "CorrectiveActionStarted",
  "doc": "Emitted when an assignee transitions a corrective action to :in_progress.",
  "fields": [
    { "name": "event_id", "type": "string" },
    { "name": "event_type", "type": "string", "default": "CorrectiveActionStarted" },
    { "name": "version", "type": "int", "default": 1 },
    { "name": "occurred_at", "type": { "type": "long", "logicalType": "timestamp-millis" } },
    { "name": "org_id", "type": "string" },
    { "name": "actor_id", "type": "string" },
    {
      "name": "subject",
      "type": {
        "type": "record",
        "name": "CorrectiveActionStartedSubject",
        "fields": [
          { "name": "action_id", "type": "string" },
          { "name": "incident_id", "type": "string" },
          { "name": "assignee_id", "type": "string" },
          { "name": "title", "type": "string" },
          { "name": "note", "type": ["null", "string"], "default": null }
        ]
      }
    },
    {
      "name": "recipient_user_ids",
      "type": { "type": "array", "items": "string" },
      "default": []
    }
  ]
}
```

`schemas/events/v1/CorrectiveActionVerified.avsc`: identical to the Started schema above, except:

- Replace every occurrence of `Started` with `Verified` (record name, subject name, and `default` in `event_type`).
- The `doc` line: `"Emitted when an investigator verifies a completed corrective action."`

`schemas/events/v1/CorrectiveActionCancelled.avsc`: identical to the Started schema, except:

- Replace every occurrence of `Started` with `Cancelled`.
- The `doc` line: `"Emitted when a corrective action is cancelled."`

- [ ] **Step 3: Restart core-api so it picks up the new schemas from the build context**

This requires a `docker compose build core-api && docker compose up -d core-api`. AvroTurf reads from `/schemas/events/v1` inside the container — see `core-api/config/initializers/avro_registry.rb`.

- [ ] **Step 4: Commit**

```bash
git add schemas/events/v1/CorrectiveActionAssigned.avsc \
        schemas/events/v1/CorrectiveActionCompleted.avsc \
        schemas/events/v1/CorrectiveActionOverdue.avsc \
        schemas/events/v1/CorrectiveActionStarted.avsc \
        schemas/events/v1/CorrectiveActionVerified.avsc \
        schemas/events/v1/CorrectiveActionCancelled.avsc
git commit -m "feat(events): add note field and three new corrective-action event types"
```

---

## Task 6: Notifier — handlers for new event types and note interpolation

**Files:**

- Modify: `notifier/app/handlers/domain_event.rb`
- Modify: `notifier/spec/consumers/corrective_actions_consumer_spec.rb`

### Steps

- [ ] **Step 1: Write the failing consumer specs**

Open `notifier/spec/consumers/corrective_actions_consumer_spec.rb`. Add (alongside the existing `CorrectiveActionCompleted` spec) two new cases, plus an update to the assigned/completed cases to verify note interpolation. Insert these as additional `it` blocks at the top of the file:

```ruby
  it 'CorrectiveActionCompleted: includes the note in the email body when present' do
    captured = []
    allow(Channels::EmailChannel).to receive(:deliver) do |user:, log:|
      captured << log
      log.mark_sent!(:email)
    end
    allow(Notifier::Models::DeliveryLog).to receive(:where).and_call_original

    produce_ca_event(
      event_id: 'evt-ca-complete-note-1',
      event_type: 'CorrectiveActionCompleted',
      recipient_ids: [reporter_id],
      actor_id: assignee_id,
      subject: { 'incident_id' => 'inc-1', 'assignee_id' => assignee_id, 'title' => 'Fix valve', 'note' => 'Replaced wheel; bearing also worn' }
    )

    consumer.consume

    rendered = Notifier::Models::DeliveryLog.where(event_id: 'evt-ca-complete-note-1').first
    expect(rendered.body).to include('Replaced wheel; bearing also worn')
  end

  it 'CorrectiveActionVerified: notifies the assignee' do
    produce_ca_event(
      event_id: 'evt-ca-verify-1',
      event_type: 'CorrectiveActionVerified',
      recipient_ids: [assignee_id],
      actor_id: third_party_actor,
      subject: { 'incident_id' => 'inc-1', 'assignee_id' => assignee_id, 'title' => 'Fix valve', 'note' => 'Looks good' }
    )

    expect { consumer.consume }
      .to change(Notifier::Models::DeliveryLog, :count).by(2)

    rows = Notifier::Models::DeliveryLog.where(event_id: 'evt-ca-verify-1').all
    expect(rows.map(&:user_id).uniq).to eq([assignee_id])
    expect(rows.first.body).to include('Looks good')
  end

  it 'CorrectiveActionCancelled: notifies the assignee with the cancellation reason' do
    produce_ca_event(
      event_id: 'evt-ca-cancel-1',
      event_type: 'CorrectiveActionCancelled',
      recipient_ids: [assignee_id],
      actor_id: third_party_actor,
      subject: { 'incident_id' => 'inc-1', 'assignee_id' => assignee_id, 'title' => 'Fix valve', 'note' => 'Superseded by action #99' }
    )

    expect { consumer.consume }
      .to change(Notifier::Models::DeliveryLog, :count).by(2)

    rows = Notifier::Models::DeliveryLog.where(event_id: 'evt-ca-cancel-1').all
    expect(rows.first.body).to include('Superseded by action #99')
  end
```

(If `DeliveryLog` does not have a `body` column, replace the `.body` assertion with `.notes` or whatever the mirror field is — read one existing notifier model row from the test DB or the migration to confirm. If no body is persisted, replace `Notifier::Models::DeliveryLog.where(...).first.body` with capturing it from the `Channels::InAppChannel.deliver` block — set up `allow(...).and_invoke ...`.)

Run the specs:

```bash
bundle exec rspec spec/consumers/corrective_actions_consumer_spec.rb
```

Expected: failures — no handler registered for `Verified` / `Cancelled`, and current handlers don't interpolate notes.

- [ ] **Step 2: Update `domain_event.rb`**

Add a small helper near the top of the file (after the `module Handlers; module DomainEvent` block, before the `# ---- Register handlers` line):

```ruby
module Handlers
  module DomainEvent
    # Returns " Note: <text>" when the event subject has a non-blank note,
    # else the empty string. Lets handlers do `body: "...#{note_suffix(event)}"`.
    def self.note_suffix(event)
      n = event.dig('subject', 'note')
      n.is_a?(String) && !n.strip.empty? ? " Note: #{n.strip}" : ''
    end
  end
end
```

Update the existing `CorrectiveActionAssigned` handler body to:

```ruby
    body: "#{Handlers::DomainEvent.actor_name(event)} assigned you a corrective action on incident ##{incident_id}: \"#{event.dig('subject', 'title')}\" (due #{event.dig('subject', 'due_date')}).#{Handlers::DomainEvent.note_suffix(event)}",
```

Update `CorrectiveActionCompleted`:

```ruby
    body: "#{Handlers::DomainEvent.actor_name(event)} marked corrective action \"#{event.dig('subject', 'title')}\" on incident ##{incident_id} as done. Review it and verify.#{Handlers::DomainEvent.note_suffix(event)}",
```

Add new handlers below the `CorrectiveActionCompleted` registration:

```ruby
Handlers::DomainEvent.register('CorrectiveActionVerified') do |event|
  incident_id = event.dig('subject', 'incident_id')
  Handlers::IncidentNotifier.notify(
    event: event,
    title: 'Corrective action verified',
    body: "#{Handlers::DomainEvent.actor_name(event)} verified corrective action \"#{event.dig('subject', 'title')}\" on incident ##{incident_id}.#{Handlers::DomainEvent.note_suffix(event)}",
    link_path: "/incidents/#{incident_id}"
  )
end

Handlers::DomainEvent.register('CorrectiveActionCancelled') do |event|
  incident_id = event.dig('subject', 'incident_id')
  Handlers::IncidentNotifier.notify(
    event: event,
    title: 'Corrective action cancelled',
    body: "#{Handlers::DomainEvent.actor_name(event)} cancelled corrective action \"#{event.dig('subject', 'title')}\" on incident ##{incident_id}.#{Handlers::DomainEvent.note_suffix(event)}",
    link_path: "/incidents/#{incident_id}"
  )
end
```

Note: `CorrectiveActionStarted` is intentionally **not** registered — see the spec out-of-scope list.

- [ ] **Step 3: Run the notifier spec**

```bash
bundle exec rspec spec/consumers/corrective_actions_consumer_spec.rb
```

Expected: all specs pass (existing 5 + the three new ones).

- [ ] **Step 4: Rebuild and restart notifier**

```bash
docker compose build notifier && docker compose up -d notifier notifier-karafka
```

- [ ] **Step 5: Commit**

```bash
git add notifier/app/handlers/domain_event.rb notifier/spec/consumers/corrective_actions_consumer_spec.rb
git commit -m "feat(notifier): handle verified/cancelled events and interpolate notes"
```

---

## Task 7: Frontend — API client and type updates

**Files:**

- Modify: `frontend/src/api/incidents.ts`
- Modify: `frontend/src/api/actions.ts` (transitionAction lives here)
- Modify: `frontend/src/types/api.ts` (add the event attribute type)

### Steps

- [ ] **Step 1: Add the event type**

Open `frontend/src/types/api.ts` and add after the existing types (e.g. near `CorrectiveActionAttributes`):

```ts
export interface CorrectiveActionEventAttributes {
  event_name: "assigned" | "started" | "completed" | "verified" | "cancelled";
  note: string | null;
  actor_id: number;
  created_at: string;
}
```

- [ ] **Step 2: Extend `createIncidentAction`'s payload**

Open `frontend/src/api/incidents.ts`. Find `createIncidentAction` and add `note?: string` to its `payload` parameter type. Example final signature (matching the existing fields):

```ts
export async function createIncidentAction(
  incidentId: string | number,
  payload: {
    title: string;
    description?: string;
    due_date: string;
    assignee_id: number;
    note?: string;
  }
) {
  // existing body — leave as-is; the existing api.post forwards the payload
  // verbatim and the controller now permits :note.
}
```

(Locate the existing function and edit the parameter type only — do not change the body if it already forwards `payload` unchanged.)

- [ ] **Step 3: Extend `transitionAction`**

Open `frontend/src/api/actions.ts`. Find `transitionAction` and add an optional `note` parameter:

```ts
export async function transitionAction(
  actionId: string | number,
  event: ActionTransition,
  note?: string
) {
  const res = await api.post<JsonApiSingle<CorrectiveActionAttributes>>(
    `/corrective_actions/${actionId}/transitions`,
    { event, note }
  );
  return res.data;
}
```

If the existing signature already uses an object payload, follow that style instead.

- [ ] **Step 4: Add `listActionEvents`**

Append to `frontend/src/api/actions.ts`:

```ts
import type { CorrectiveActionEventAttributes } from "@/types/api";

export async function listActionEvents(actionId: string | number) {
  const res = await api.get<JsonApiList<CorrectiveActionEventAttributes>>(
    `/corrective_actions/${actionId}/events`
  );
  return res.data;
}
```

- [ ] **Step 5: Verify the build**

```bash
cd frontend
pnpm run build
```

Expected: builds clean (the existing call sites still type-check because the new parameter is optional).

- [ ] **Step 6: Commit**

```bash
git add frontend/src/api/incidents.ts frontend/src/api/actions.ts frontend/src/types/api.ts
git commit -m "feat(frontend): extend API client with note parameter and events feed"
```

---

## Task 8: Frontend — transition modal and new-action note field

**Files:**

- Modify: `frontend/src/views/IncidentDetail.vue`

This task adds a small reusable transition dialog and rewires the existing transition buttons. Because of the file's size, scope the change strictly to the corrective-actions section; do not touch incident-level controls.

### Steps

- [ ] **Step 1: Add the new-action note textarea**

In `IncidentDetail.vue`, find the new-action form (the `<n-form-item>` rows around the `Title`, `Description`, `Due date`, `Assignee` fields). Add a new form item between `Description` and `Due date`:

```vue
<n-form-item label="Note for assignee (optional)">
  <n-input
    v-model:value="newAction.note"
    type="textarea"
    :autosize="{ minRows: 2, maxRows: 4 }"
    placeholder="Why are you assigning this now? Context for the worker."
  />
</n-form-item>
```

Add `note: ""` to the reactive `newAction` initial value (near the top of `<script setup>`):

```ts
const newAction = ref({
  title: "",
  description: "",
  note: "",
  due_date: null as string | null,
  assignee_id: null as number | null
});
```

In the existing `createAction` (or whatever the submit handler is named) function, include `note` in the call:

```ts
await createIncidentAction(incidentId.value, {
  title: newAction.value.title,
  description: newAction.value.description,
  note: newAction.value.note || undefined,
  due_date: newAction.value.due_date!,
  assignee_id: newAction.value.assignee_id!
});
```

Reset `note: ""` in the post-submit reset block.

- [ ] **Step 2: Add a transition-note modal**

In the same file's `<template>`, near the bottom of the corrective-actions section, add:

```vue
<n-modal
  v-model:show="transitionDialog.show"
  preset="dialog"
  :title="transitionDialog.title"
  positive-text="Confirm"
  negative-text="Cancel"
  @positive-click="confirmTransition"
  @negative-click="transitionDialog.show = false"
>
  <n-input
    v-model:value="transitionDialog.note"
    type="textarea"
    :autosize="{ minRows: 2, maxRows: 6 }"
    placeholder="Optional note"
  />
</n-modal>
```

Add to `<script setup>`:

```ts
const transitionDialog = ref<{
  show: boolean;
  title: string;
  actionId: string | number | null;
  event: ActionTransition | null;
  note: string;
}>({
  show: false,
  title: "",
  actionId: null,
  event: null,
  note: ""
});

function openTransitionDialog(actionId: string | number, event: ActionTransition) {
  const titles: Record<ActionTransition, string> = {
    start: "Start action",
    complete: "Mark as done",
    verify: "Verify action",
    cancel: "Cancel action"
  };
  transitionDialog.value = {
    show: true,
    title: titles[event],
    actionId,
    event,
    note: ""
  };
}

async function confirmTransition() {
  const { actionId, event, note } = transitionDialog.value;
  if (!actionId || !event) return;
  try {
    await transitionAction(actionId, event, note || undefined);
    transitionDialog.value.show = false;
    await loadAux(); // existing helper that refetches actions
    message.success(`Action ${event}d`);
  } catch (e) {
    message.error(`Transition failed: ${(e as ApiError).message}`);
  }
}
```

Find every existing transition trigger (`@click="transitionAction(...)"` calls within the actions list) and replace them with `@click="openTransitionDialog(a.id, '<event>')"` — preserving the same per-event allow-list that the existing `allowedForAction()` returns.

- [ ] **Step 3: Verify**

```bash
cd frontend
pnpm run build
pnpm run lint
```

Expected: both green.

- [ ] **Step 4: Commit**

```bash
git add frontend/src/views/IncidentDetail.vue
git commit -m "feat(frontend): collect optional note on new action and every transition"
```

---

## Task 9: Frontend — Activity tab

**Files:**

- Modify: `frontend/src/views/IncidentDetail.vue`

### Steps

- [ ] **Step 1: Add the events store and loader**

In `<script setup>`:

```ts
import { listActionEvents } from "@/api/actions";
import type { CorrectiveActionEventAttributes } from "@/types/api";

interface ActionEventRow {
  id: string;
  event_name: CorrectiveActionEventAttributes["event_name"];
  note: string | null;
  actor_id: number;
  created_at: string;
}

const actionEvents = ref<Record<string, ActionEventRow[]>>({});

async function loadActionEvents(actionId: string) {
  try {
    const res = await listActionEvents(actionId);
    actionEvents.value = {
      ...actionEvents.value,
      [actionId]: res.data.map((r) => ({
        id: r.id,
        event_name: r.attributes.event_name,
        note: r.attributes.note,
        actor_id: r.attributes.actor_id,
        created_at: r.attributes.created_at
      }))
    };
  } catch (e) {
    message.error(`Could not load activity: ${(e as ApiError).message}`);
  }
}
```

Call `loadActionEvents(a.id)` whenever an action row expands. If the existing UI uses an inline expandable row, hook into its `@update:expanded-row-keys` or equivalent.

- [ ] **Step 2: Render the timeline**

Inside the expanded-row template for a corrective action (or a new tab if the row already has tabs), add:

```vue
<div class="action-activity">
  <h4>Activity</h4>
  <n-empty
    v-if="!(actionEvents[a.id] && actionEvents[a.id].length)"
    description="No activity yet."
  />
  <n-timeline v-else>
    <n-timeline-item
      v-for="evt in actionEvents[a.id]"
      :key="evt.id"
      :type="timelineType(evt.event_name)"
      :title="timelineTitle(evt)"
      :content="evt.note || ''"
      :time="formatDateTime(evt.created_at)"
    />
  </n-timeline>
</div>
```

Add helpers:

```ts
function timelineType(name: CorrectiveActionEventAttributes["event_name"]) {
  switch (name) {
    case "assigned":  return "info";
    case "started":   return "default";
    case "completed": return "success";
    case "verified":  return "success";
    case "cancelled": return "error";
    default:          return "default";
  }
}

function timelineTitle(evt: ActionEventRow) {
  const actor = orgUsers.value.find((u) => Number(u.id) === evt.actor_id);
  const who = actor?.name ?? `User #${evt.actor_id}`;
  const labels: Record<CorrectiveActionEventAttributes["event_name"], string> = {
    assigned:  "assigned",
    started:   "started",
    completed: "marked as done",
    verified:  "verified",
    cancelled: "cancelled"
  };
  return `${who} ${labels[evt.event_name]}`;
}
```

(`formatDateTime` likely already exists in `utils/format.ts` — reuse it.)

- [ ] **Step 3: Verify**

```bash
pnpm run build
pnpm run lint
```

- [ ] **Step 4: Commit**

```bash
git add frontend/src/views/IncidentDetail.vue
git commit -m "feat(frontend): show chronological activity feed for each corrective action"
```

---

## Task 10: Documentation

**Files:**

- Modify: `docs/use-cases/use-cases.md`
- Modify: `docs/design/state-machines.md`
- Modify: `docs/design/event-contract.md`
- Modify: `docs/design/domain-model.md`
- Modify: `docs/design/api.md`
- Modify: `CHANGELOG.md`
- Modify: `core-api/openapi.yaml` (regenerated, see Step 7)

### Steps

- [ ] **Step 1: `docs/use-cases/use-cases.md`**

In the UC3 row ("Complete assigned action"), append the new behavior in the success-criterion column: replace "Action moves to `done`; investigator receives notification" with "Action moves to `done`; investigator receives a notification that includes the worker's optional completion note." In the UC7 row, add a sentence about the optional assignment note that becomes the first entry in the action's activity feed.

- [ ] **Step 2: `docs/design/state-machines.md`**

Under the "Corrective Action" heading, add a paragraph after the transitions list:

> Every transition (including the implicit `assigned` at creation) writes a row to `corrective_action_events` with the actor, timestamp, and an optional free-text note. The same callback emits the corresponding outbox event (`CorrectiveActionAssigned`, `CorrectiveActionStarted`, `CorrectiveActionCompleted`, `CorrectiveActionVerified`, `CorrectiveActionCancelled`). The note travels in the Avro subject so notifier handlers can interpolate it without re-querying the audit log.

- [ ] **Step 3: `docs/design/event-contract.md`**

Update the `corrective_actions.v1` row in the topics table to list all event types now emitted: `CorrectiveActionAssigned`, `CorrectiveActionStarted`, `CorrectiveActionCompleted`, `CorrectiveActionVerified`, `CorrectiveActionCancelled`, `CorrectiveActionOverdue`. Below the table, add a sentence: "All corrective-action events share an optional `note: ["null", "string"]` field on their subject record, carrying the operator-provided context for that transition."

- [ ] **Step 4: `docs/design/domain-model.md`**

In the ERD section, add `CorrectiveActionEvent` as a child of `CorrectiveAction` with fields `event_name`, `actor_id`, `note`, `created_at`. In the "Versions vs audit" paragraph (or wherever PaperTrail versions are discussed), add: "`corrective_action_events` is a domain audit log distinct from PaperTrail's `versions` table — it captures *who made which transition with what note*, while `versions` capture *what attribute diffs were applied*."

- [ ] **Step 5: `docs/design/api.md`**

Update the row for "Corrective actions" to include the events endpoint:

```
| Corrective actions | `GET/PATCH /corrective_actions/:id`, `POST /corrective_actions/:id/transitions`, `GET /corrective_actions/:id/events` |
```

Add a note below the table: "The create endpoint and the `/transitions` endpoint both accept an optional `note` field; the value is recorded on the resulting `corrective_action_events` row and included in the outbox payload."

- [ ] **Step 6: `CHANGELOG.md`**

Add under the unreleased section:

```markdown
### Added
- Corrective actions: optional free-text note on create and every state transition (start/complete/verify/cancel). Notes appear in the email + in-app notification body and on a new chronological Activity feed.
- New endpoint `GET /api/v1/corrective_actions/:id/events` returning the action's audit log.
- New Avro event types `CorrectiveActionStarted`, `CorrectiveActionVerified`, `CorrectiveActionCancelled`.
```

- [ ] **Step 7: Regenerate `openapi.yaml`**

The OpenAPI spec is generated from rswag request specs.

```bash
cd core-api
set -a && source ../.env && set +a
export POSTGRES_HOST=127.0.0.1 RAILS_ENV=test
bundle exec rake rswag:specs:swaggerize
```

Inspect `git diff core-api/openapi.yaml`: confirm new operations and the `note` parameter appear, and nothing unrelated changed.

- [ ] **Step 8: Commit**

```bash
git add docs/ CHANGELOG.md core-api/openapi.yaml
git commit -m "docs: corrective-action transition notes (UC3 update, ERD, event contract, OpenAPI)"
```

---

## Task 11: End-to-end smoke test

This task is not a commit — it is a verification ritual after Task 9 is merged.

### Steps

- [ ] **Step 1: Rebuild and restart all services**

```bash
docker compose build core-api notifier
docker compose up -d core-api sidekiq notifier notifier-karafka
```

Wait for `curl -sf http://localhost:3000/healthz` to return ok.

- [ ] **Step 2: Drive the flow via curl**

Reuse the script-shape from the previous walkthrough. As Pat (investigator), create an action with a note. As Wendy (worker), start it with a note, then complete with a note. As Pat again, verify with a note.

```bash
PAT=$(curl -s -X POST http://localhost:3000/api/v1/auth/login -H "Content-Type: application/json" -d '{"user":{"email":"investigator@acme.demo","password":"password"}}' | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')

DUE=$(date -u -v+7d +"%Y-%m-%dT%H:%M:%SZ")
ACTION=$(curl -s -X POST http://localhost:3000/api/v1/incidents/39/corrective_actions \
  -H "Authorization: Bearer $PAT" -H "Content-Type: application/json" \
  -d "{\"corrective_action\":{\"title\":\"Smoke test\",\"description\":\"x\",\"assignee_id\":3,\"due_date\":\"$DUE\",\"note\":\"Found during walkthrough\"}}" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["data"]["id"])')

WENDY=$(curl -s -X POST http://localhost:3000/api/v1/auth/login -H "Content-Type: application/json" -d '{"user":{"email":"worker@acme.demo","password":"password"}}' | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')

curl -s -X POST "http://localhost:3000/api/v1/corrective_actions/$ACTION/transitions" \
  -H "Authorization: Bearer $WENDY" -H "Content-Type: application/json" \
  -d '{"event":"start","note":"Beginning now"}'

curl -s -X POST "http://localhost:3000/api/v1/corrective_actions/$ACTION/transitions" \
  -H "Authorization: Bearer $WENDY" -H "Content-Type: application/json" \
  -d '{"event":"complete","note":"Replaced wheel, bearing seems worn"}'

curl -s "http://localhost:3000/api/v1/corrective_actions/$ACTION/events" -H "Authorization: Bearer $PAT" | python3 -m json.tool
```

- [ ] **Step 3: Verify expected outcomes**

- The events list returns three rows: `assigned`, `started`, `completed` — each with the correct note and actor.
- Mailcatcher (http://localhost:1080) shows two new emails: one to Wendy ("Corrective action assigned ... Note: Found during walkthrough") and one to Pat ("ready to verify ... Note: Replaced wheel, bearing seems worn").
- `outbox_events` rows have the note inside `payload->'subject'->>'note'`.

Done. The branch is ready to push.

---

## Notes for the implementer

- **Existing conventions:** the codebase prefers thin controllers + fat models, Pundit policies per aggregate, JSON:API serializers, and AASM `after` callbacks for transactional side-effects. Match those.
- **Don't add error handling that the existing layer doesn't need.** `BaseController` already rescues `Pundit::NotAuthorizedError`, `RecordNotFound`, and `RecordInvalid`. Let exceptions bubble.
- **One thing to watch:** the `OutboxShipperJob` reads from the `outbox_events` table and ships rows it hasn't published. If you add a new event_type and Karapace has not seen its schema yet, AvroTurf auto-registers on first encode. No manual schema-registration step is needed.
- **`pending_note` is request-scoped state on a model instance.** It is set immediately before `aasm_event!` is called and cleared inside `log_transition!`. Do not move it elsewhere.
