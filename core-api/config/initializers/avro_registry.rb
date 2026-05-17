# ============================================================================
# Avro + Karapace (open-source Schema Registry) wiring.
#
# AvroTurf::Messaging caches schemas in-process and prepends the Confluent
# wire-format header to messages (0x00 + <4-byte schema_id> + Avro payload).
# ============================================================================

require "avro_turf/messaging"

Rails.application.config.to_prepare do
  Rails.application.config.avro_messaging ||= AvroTurf::Messaging.new(
    registry_url:    ENV.fetch("KARAPACE_URL", "http://karapace:8081"),
    schemas_path:    Rails.root.join("../schemas/events/v1").to_s,
    namespace:       "com.ehs.events.v1",
    logger:          Rails.logger
  )
end
