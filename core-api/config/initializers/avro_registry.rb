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
    # NOTE: do NOT pass `namespace:` — AvroTurf::Messaging would map it to a
    # directory prefix, but our schemas live flat under schemas/events/v1/.
    # The Avro namespace inside each .avsc is what the registry stores.
    @client ||= AvroTurf::Messaging.new(
      registry_url: ENV.fetch("KARAPACE_URL", "http://karapace:8081"),
      # Inside the container the schemas live at /schemas/events/v1/ (copied
      # via the `schemas` named build context). Locally on the host, fall back
      # to ../schemas/events/v1 relative to Rails.root.
      schemas_path: File.directory?("/schemas/events/v1") ? "/schemas/events/v1" : Rails.root.join("../schemas/events/v1").to_s,
      logger:       Rails.logger
    )
  end

  def self.reset!
    @client = nil
  end
end
