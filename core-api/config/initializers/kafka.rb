# ============================================================================
# rdkafka producer — used by OutboxShipperJob to publish events to Kafka.
#
# Reads broker list, optional SASL/SCRAM, and TLS settings from ENV. Configured
# for at-least-once delivery (acks=all, idempotence on) — outbox already gives
# us exactly-once-effective via event_id idempotency in the consumer.
# ============================================================================

require "rdkafka"

module EhsKafka
  CONFIG = {
    "bootstrap.servers"           => ENV.fetch("KAFKA_BROKERS", "kafka:9092"),
    "acks"                        => "all",
    "enable.idempotence"          => "true",
    "compression.type"            => "snappy",
    "client.id"                   => "ehs-core-api",
    "message.send.max.retries"    => "5"
  }.tap do |c|
    if ENV["KAFKA_SECURITY_PROTOCOL"]&.start_with?("SASL")
      c["security.protocol"] = ENV.fetch("KAFKA_SECURITY_PROTOCOL")
      c["sasl.mechanisms"]   = ENV.fetch("KAFKA_SASL_MECHANISM", "SCRAM-SHA-512")
      c["sasl.username"]     = ENV.fetch("KAFKA_SASL_USERNAME")
      c["sasl.password"]     = ENV.fetch("KAFKA_SASL_PASSWORD")
    end
    if ENV["KAFKA_TLS_CA_FILE"]
      c["ssl.ca.location"] = ENV.fetch("KAFKA_TLS_CA_FILE")
    end
  end.freeze

  def self.producer
    @producer ||= Rdkafka::Config.new(CONFIG).producer
  end
end
