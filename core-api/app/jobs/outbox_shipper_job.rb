# Ships pending outbox_events to Kafka. Scheduled by sidekiq-cron every 5s
# (see config/sidekiq.yml). Idempotent — every event carries event_id, the
# consumer dedupes via delivery_log unique index, so re-shipping a row twice
# is harmless.
#
# Currently publishes JSON payloads (encoded via AvroMessaging when the schema
# is registered; falls back to JSON during early bootstrap). The notifier
# accepts either since AvroTurf::Messaging.decode raises a clear error on
# format mismatch and the consumer retry will surface the issue.
class OutboxShipperJob
  include Sidekiq::Job
  sidekiq_options queue: "outbox", retry: 5

  BATCH_SIZE = 100

  def perform
    rows = OutboxEvent.pending.limit(BATCH_SIZE).to_a
    return if rows.empty?

    rows.each do |row|
      ship_one(row)
    rescue StandardError => e
      Rails.logger.error("[outbox] failed event_id=#{row.event_id} #{e.class}: #{e.message}")
      row.mark_failed!(e.message)
      raise if rows.size == 1   # let Sidekiq retry on isolated failures
    end
  end

  private

  def ship_one(row)
    payload_bytes = encode(row)

    producer = EhsKafka.producer
    handle   = producer.produce(
      topic:     row.topic,
      key:       row.partition_key,
      payload:   payload_bytes,
      headers:   { "event_type" => row.event_type, "event_id" => row.event_id }
    )
    handle.wait(max_wait_timeout_ms: 5_000)
    row.mark_published!
  end

  # Encode using Avro+Karapace when the matching schema is registered; otherwise
  # JSON fallback. This keeps the system working during early bootstrap when
  # Avro schemas may not be registered yet, and during local debugging.
  def encode(row)
    # schema_name matches the .avsc filename and the record name inside it
    # (PascalCase, e.g. "IncidentSubmitted"). This is the avro-turf convention.
    AvroMessaging.client.encode(row.payload.deep_stringify_keys, schema_name: row.event_type)
  rescue StandardError => e
    Rails.logger.warn("[outbox] Avro encode failed (#{e.class}: #{e.message}); falling back to JSON")
    row.payload.to_json
  end
end
