require "spec_helper"

RSpec.describe CorrectiveActionsConsumer do
  subject(:consumer) { karafka.consumer_for("corrective_actions.v1") }

  let(:org_id)      { "org-2" }
  let(:reporter_id) { "user-ca-reporter" }
  let(:assignee_id) { "user-ca-assignee" }
  # IncidentNotifier strips actor_id from recipients to avoid self-notifications.
  let(:third_party_actor) { "user-ca-actor" }

  before do
    Notifier::Models::UserMirror.upsert(
      user_id: reporter_id, org_id: org_id, role: "WORKER",
      name: "CA Reporter", email: "ca-reporter@example.com", telegram_chat_id: nil,
      prefs: {}, updated_at: Time.now.utc
    )
    Notifier::Models::UserMirror.upsert(
      user_id: assignee_id, org_id: org_id, role: "INVESTIGATOR",
      name: "CA Assignee", email: "ca-assignee@example.com", telegram_chat_id: nil,
      prefs: {}, updated_at: Time.now.utc
    )

    allow(Channels::EmailChannel).to receive(:deliver) { |user:, log:| log.mark_sent!(:email) }
    allow(Channels::TelegramChannel).to receive(:deliver) { |user:, log:| log.mark_sent!(:telegram) }
    stub_const("Notifier::Web::WsServer", Module.new { def self.push(*); end })
  end

  def produce_ca_event(event_id:, event_type:, recipient_ids:, subject: {}, actor_id: third_party_actor)
    payload = JSON.generate(
      "event_id"           => event_id,
      "event_type"         => event_type,
      "version"            => 1,
      "occurred_at"        => Time.now.utc.iso8601,
      "org_id"             => org_id,
      "actor_id"           => actor_id,
      "subject"            => {
        "action_id" => "ca-99", "title" => "Fix valve", "due_date" => "2026-06-01"
      }.merge(subject),
      "recipient_user_ids" => recipient_ids
    )
    karafka.produce(payload, topic: "corrective_actions.v1")
  end

  # ---------------------------------------------------------------------------
  # 6. CorrectiveActionAssigned — assignee gets email + in_app
  # ---------------------------------------------------------------------------
  it "CorrectiveActionAssigned: notifies the assignee" do
    produce_ca_event(
      event_id:      "evt-ca-assign-1",
      event_type:    "CorrectiveActionAssigned",
      recipient_ids: [assignee_id]
    )

    expect { consumer.consume }
      .to change(Notifier::Models::DeliveryLog, :count).by(2)

    rows = Notifier::Models::DeliveryLog.where(event_id: "evt-ca-assign-1").all
    expect(rows.map(&:user_id).uniq).to eq([assignee_id])
    expect(rows.map(&:channel).sort).to eq(%w[email in_app])
  end

  # ---------------------------------------------------------------------------
  # 7. CorrectiveActionOverdue — reporter + assignee both notified
  # ---------------------------------------------------------------------------
  it "CorrectiveActionOverdue: notifies reporter and assignee" do
    produce_ca_event(
      event_id:      "evt-ca-overdue-1",
      event_type:    "CorrectiveActionOverdue",
      recipient_ids: [reporter_id, assignee_id],
      subject:       { "action_id" => "ca-99", "title" => "Fix valve", "days_overdue" => 3 }
    )

    expect { consumer.consume }
      .to change(Notifier::Models::DeliveryLog, :count).by(4) # 2 users x 2 channels

    rows = Notifier::Models::DeliveryLog.where(event_id: "evt-ca-overdue-1").all
    expect(rows.map(&:user_id).uniq.sort).to eq([assignee_id, reporter_id].sort)
  end

  # ---------------------------------------------------------------------------
  # 8. Malformed message (no event_id) — skips cleanly, no row, no raise
  # ---------------------------------------------------------------------------
  it "skips a malformed message that is missing event_id without raising" do
    karafka.produce(
      JSON.generate("event_type" => "CorrectiveActionAssigned", "org_id" => org_id),
      topic: "corrective_actions.v1"
    )

    expect { consumer.consume }.not_to raise_error
    expect(Notifier::Models::DeliveryLog.count).to eq(0)
  end

  # ---------------------------------------------------------------------------
  # 9. De-dup across CorrectiveActions topic
  # ---------------------------------------------------------------------------
  it "is idempotent: the same (event_id, user_id, channel) triple is not duplicated" do
    payload = JSON.generate(
      "event_id" => "evt-ca-dedup-1", "event_type" => "CorrectiveActionAssigned",
      "version" => 1, "occurred_at" => Time.now.utc.iso8601, "org_id" => org_id,
      "actor_id" => third_party_actor,
      "subject" => { "action_id" => "ca-99", "title" => "Fix valve", "due_date" => "2026-06-01" },
      "recipient_user_ids" => [assignee_id]
    )

    karafka.produce(payload, topic: "corrective_actions.v1")
    consumer.consume
    first_count = Notifier::Models::DeliveryLog.where(event_id: "evt-ca-dedup-1").count

    karafka.produce(payload, topic: "corrective_actions.v1")
    consumer.consume
    expect(Notifier::Models::DeliveryLog.where(event_id: "evt-ca-dedup-1").count).to eq(first_count)
  end
end
