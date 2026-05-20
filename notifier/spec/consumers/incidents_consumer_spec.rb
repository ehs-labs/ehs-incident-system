# frozen_string_literal: true

require 'spec_helper'

# Consumer specs use karafka-testing's in-memory broker.
# Payloads are produced as JSON (the AvroDeserializer falls back to JSON.parse
# for any message that does not start with the Confluent magic byte 0x00).
RSpec.describe IncidentsConsumer do
  subject(:consumer) { karafka.consumer_for('incidents.v1') }

  let(:org_id)       { 'org-1' }
  let(:reporter_id)  { 'user-reporter' }
  let(:assignee_id)  { 'user-assignee' }
  # IncidentNotifier strips actor_id from recipients to avoid self-notifications,
  # so tests pick an actor distinct from any recipient under test.
  let(:third_party_actor) { 'user-other' }

  before do
    Notifier::Models::UserMirror.upsert(
      user_id: reporter_id, org_id: org_id, role: 'WORKER',
      name: 'Reporter', email: 'reporter@example.com', telegram_chat_id: nil,
      prefs: {}, updated_at: Time.now.utc
    )
    Notifier::Models::UserMirror.upsert(
      user_id: assignee_id, org_id: org_id, role: 'INVESTIGATOR',
      name: 'Assignee', email: 'assignee@example.com', telegram_chat_id: nil,
      prefs: {}, updated_at: Time.now.utc
    )

    # Stub EmailChannel so no SMTP connection is attempted.
    allow(Channels::EmailChannel).to receive(:deliver) { |user:, log:| log.mark_sent!(:email) }
    # Stub TelegramChannel — bot bridge not implemented yet.
    allow(Channels::TelegramChannel).to receive(:deliver) { |user:, log:| log.mark_sent!(:telegram) }
    # InAppChannel only writes to DB; allow the real implementation.
    stub_const('Notifier::Web::WsServer', Module.new { def self.push(*); end })
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def produce_incident_event(event_id:, event_type:, recipient_ids:, subject: {}, actor_id: third_party_actor)
    payload = JSON.generate(
      'event_id' => event_id,
      'event_type' => event_type,
      'version' => 1,
      'occurred_at' => Time.now.utc.iso8601,
      'org_id' => org_id,
      'actor_id' => actor_id,
      'subject' => { 'incident_id' => 'inc-1', 'severity' => 2, 'summary' => 'Spill' }.merge(subject),
      'recipient_user_ids' => recipient_ids
    )
    karafka.produce(payload, topic: 'incidents.v1')
  end

  def delivery_logs_for(event_id)
    Notifier::Models::DeliveryLog.where(event_id: event_id).all
  end

  # ---------------------------------------------------------------------------
  # 1. IncidentSubmitted — email + in_app rows for each recipient
  # ---------------------------------------------------------------------------
  it 'IncidentSubmitted: writes email and in_app delivery_log rows for each recipient' do
    produce_incident_event(
      event_id: 'evt-submit-1',
      event_type: 'IncidentSubmitted',
      recipient_ids: [reporter_id, assignee_id]
    )

    expect { consumer.consume }
      .to change(Notifier::Models::DeliveryLog, :count).by(4) # 2 recipients x 2 channels

    rows = delivery_logs_for('evt-submit-1')
    expect(rows.map(&:channel).uniq.sort).to eq(%w[email in_app])
    expect(rows.map(&:user_id).uniq.sort).to eq([assignee_id, reporter_id].sort)
  end

  # ---------------------------------------------------------------------------
  # 2. IncidentAssigned — only the assignee is notified
  # ---------------------------------------------------------------------------
  it 'IncidentAssigned: writes delivery_log rows for the assignee only' do
    produce_incident_event(
      event_id: 'evt-assign-1',
      event_type: 'IncidentAssigned',
      recipient_ids: [assignee_id]
    )

    expect { consumer.consume }
      .to change(Notifier::Models::DeliveryLog, :count).by(2) # email + in_app

    rows = delivery_logs_for('evt-assign-1')
    expect(rows.map(&:user_id).uniq).to eq([assignee_id])
    expect(rows.map(&:event_type).uniq).to eq(['IncidentAssigned'])
  end

  # ---------------------------------------------------------------------------
  # 3. De-dup: same (event_id, user_id, channel) consumed twice yields one row
  # ---------------------------------------------------------------------------
  it 'is idempotent: re-consuming the same message does not create duplicate rows' do
    2.times do
      produce_incident_event(
        event_id: 'evt-dedup-1',
        event_type: 'IncidentSubmitted',
        recipient_ids: [reporter_id]
      )
    end

    consumer.consume
    initial_count = Notifier::Models::DeliveryLog.where(event_id: 'evt-dedup-1').count

    # Simulate the consumer being called again with the same messages already in buffer
    # by re-producing and re-consuming — the claim method must block duplicates.
    karafka.produce(
      JSON.generate(
        'event_id' => 'evt-dedup-1', 'event_type' => 'IncidentSubmitted',
        'version' => 1, 'occurred_at' => Time.now.utc.iso8601, 'org_id' => org_id,
        'actor_id' => third_party_actor,
        'subject' => { 'incident_id' => 'inc-1', 'severity' => 2, 'summary' => 'Spill' },
        'recipient_user_ids' => [reporter_id]
      ),
      topic: 'incidents.v1'
    )
    consumer.consume

    expect(Notifier::Models::DeliveryLog.where(event_id: 'evt-dedup-1').count).to eq(initial_count)
  end

  # ---------------------------------------------------------------------------
  # 4. Malformed message (no event_id) — skips cleanly, no row, no raise
  # ---------------------------------------------------------------------------
  it 'skips a malformed message that is missing event_id without raising' do
    karafka.produce(
      JSON.generate('event_type' => 'IncidentSubmitted', 'org_id' => org_id),
      topic: 'incidents.v1'
    )

    expect { consumer.consume }.not_to raise_error
    expect(Notifier::Models::DeliveryLog.count).to eq(0)
  end

  # ---------------------------------------------------------------------------
  # 5. Unrecognized event_type — dispatched but silently ignored (no handler)
  # ---------------------------------------------------------------------------
  it 'silently ignores events with an unregistered event_type' do
    produce_incident_event(
      event_id: 'evt-unknown-1',
      event_type: 'UnknownEvent',
      recipient_ids: [reporter_id]
    )

    expect { consumer.consume }.not_to raise_error
    expect(Notifier::Models::DeliveryLog.count).to eq(0)
  end
end
