# ============================================================================
# Avro + Karapace (open-source Schema Registry) wiring.
#
# AvroTurf::Messaging caches schemas in-process and prepends the Confluent
# wire-format header to messages (0x00 + <4-byte schema_id> + Avro payload).
# ============================================================================

require "avro_turf/messaging"

# AvroTurf::Messaging caches schemas in-process and prepends the Confluent
# wire-format header to messages (0x00 + <4-byte schema_id> + Avro payload).
# Lazily built on first call so it doesn't block app boot if Karapace is unavailable.
module AvroMessaging
  def self.client
    @client ||= AvroTurf::Messaging.new(
      registry_url: ENV.fetch("KARAPACE_URL", "http://karapace:8081"),
      schemas_path: Rails.root.join("../schemas/events/v1").to_s,
      namespace:    "com.ehs.events.v1",
      logger:       Rails.logger
    )
  end

  def self.reset!
    @client = nil
  end
end
