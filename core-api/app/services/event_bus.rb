require "ulid"

# EventBus writes domain events to outbox_events inside the current DB
# transaction. OutboxShipperJob ships them to Kafka asynchronously.
#
# This is the canonical entry point for emitting events; AASM after_transition
# callbacks call EventBus.publish! and never touch Kafka directly. That gives
# us the "transactional outbox" guarantee — events are visible to consumers
# if and only if the underlying state change is committed.
module EventBus
  module_function

  # @param event_type [String]   e.g. "IncidentSubmitted"
  # @param topic      [String]   e.g. "incidents.v1"
  # @param partition_key [String]  org_id (preserves per-tenant ordering)
  # @param org_id     [Integer]
  # @param actor_id   [Integer]  the user who caused this event
  # @param subject    [Hash]     event-type-specific payload
  # @param recipient_user_ids [Array<Integer>]  who the notifier should fan out to
  # @param event_id   [String]   optional ULID; generated if absent (idempotency key)
  def publish!(event_type:, topic:, partition_key:, org_id:, actor_id:, subject:,
               recipient_user_ids: [], event_id: nil)
    generated_id = event_id || ULID.generate

    OutboxEvent.create!(
      event_id:      generated_id,
      event_type:    event_type,
      topic:         topic,
      partition_key: partition_key.to_s,
      payload:       {
        event_id:           generated_id,
        event_type:         event_type,
        version:            1,
        # Avro logical type timestamp-millis is `long` (epoch ms)
        occurred_at:        (Time.current.to_f * 1000).to_i,
        org_id:             org_id.to_s,
        actor_id:           actor_id.to_s,
        subject:            subject.compact.transform_keys(&:to_s).transform_values { |v| coerce(v) },
        recipient_user_ids: recipient_user_ids.map(&:to_s)
      }
    )
  end

  # Coerce Ruby values to Avro-friendly primitives. Integers stay Integer
  # (Avro int / long); Time/Date map to logical-type ints; everything else
  # gets stringified.
  def coerce(v)
    case v
    when Integer, Float       then v
    when Time, DateTime       then (v.to_f * 1000).to_i
    when Date                 then (v.to_time.to_i / 86_400).to_i
    when TrueClass, FalseClass then v
    else                            v.to_s
    end
  end
end
