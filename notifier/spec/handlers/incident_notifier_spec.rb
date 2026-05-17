require "spec_helper"

# Smoke spec for the IncidentNotifier handler — verifies the recipient lookup
# and delivery_log claim/idempotency wiring, without actually sending email
# (the EmailChannel and InAppChannel are stubbed).
RSpec.describe Handlers::IncidentNotifier do
  let(:user_id) { "9001" }

  before do
    DB[:delivery_log].truncate
    DB[:users_mirror].truncate
    Notifier::Models::UserMirror.upsert(
      user_id: user_id, org_id: "1", role: "WORKER",
      name: "Test Worker", email: "test@example.com", telegram_chat_id: nil,
      prefs: {}, updated_at: Time.now.utc
    )
  end

  let(:event) do
    {
      "event_id"           => "01ABCDEFTEST",
      "event_type"         => "IncidentSubmitted",
      "version"            => 1,
      "occurred_at"        => Time.now.utc,
      "org_id"             => "1",
      "actor_id"           => user_id,
      "subject"            => { "incident_id" => "42", "severity" => 2, "summary" => "Test", "site_id" => "1", "reporter_id" => user_id },
      "recipient_user_ids" => [user_id]
    }
  end

  it "fans out to the configured channels and writes delivery_log rows" do
    allow(Channels::EmailChannel).to receive(:deliver) do |user:, log:|
      log.mark_sent!(:email)
    end
    allow(Channels::InAppChannel).to receive(:deliver) do |user:, log:|
      log.mark_sent!(:in_app)
    end

    described_class.notify(
      event:     event,
      title:     "Test title",
      body:      "Test body",
      link_path: "/incidents/42"
    )

    rows = Notifier::Models::DeliveryLog.where(event_id: event.fetch("event_id")).all
    expect(rows.map(&:channel)).to match_array(%w[email in_app])
    expect(rows.map(&:state).uniq).to eq(["sent"])
  end

  it "is idempotent: re-running the same event does not duplicate delivery rows" do
    allow(Channels::EmailChannel).to receive(:deliver) { |user:, log:| log.mark_sent!(:email) }
    allow(Channels::InAppChannel).to receive(:deliver) { |user:, log:| log.mark_sent!(:in_app) }

    2.times do
      described_class.notify(event: event, title: "T", body: "B", link_path: "/x")
    end

    expect(Notifier::Models::DeliveryLog.where(event_id: event.fetch("event_id")).count).to eq(2) # email + in_app, one each
  end
end
