# frozen_string_literal: true

# ============================================================================
# Karafka boot file — the `karafka server` CLI looks for this at app root.
#
# Loads our shared Rack/Sequel boot (which wires the DB, FIELD_CIPHER, and
# Bundler gems), then defines the Karafka app + Avro deserializer + routes.
# ============================================================================

require_relative 'config/boot'

# Karafka's logger writes to stdout via the configured Ruby Logger; force the
# stream to flush per-line so container logs surface in real time.
$stdout.sync = true
$stderr.sync = true

require 'karafka'
require 'avro_turf/messaging'

# -----------------------------------------------------------------------------
# Avro deserializer — resolves schemas by ID from Karapace.
# Each message starts with the Confluent wire-format header
#   0x00 + <4-byte schema_id> + Avro payload
# so the registry lookup is keyed on schema_id, not on schema name.
# Tombstones in compacted topics arrive with a nil payload — return nil so the
# consumer can branch on it.
# -----------------------------------------------------------------------------
AVRO_MESSAGING = AvroTurf::Messaging.new(
  registry_url: ENV.fetch('KARAPACE_URL', 'http://karapace:8081'),
  schemas_path: if File.directory?('/schemas/events/v1')
                  '/schemas/events/v1'
                else
                  File.expand_path('../schemas/events/v1',
                                   __dir__)
                end
)

class AvroDeserializer
  MAGIC_BYTE = "\x00".b.freeze

  def call(message)
    raw = message.raw_payload
    return nil if raw.nil?

    # Confluent wire format begins with magic byte 0x00 followed by schema id.
    # During early bootstrap the producer may have fallen back to JSON when
    # the Avro schema was not registered yet; detect that case and parse it.
    if raw.start_with?(MAGIC_BYTE)
      AVRO_MESSAGING.decode(raw)
    else
      JSON.parse(raw)
    end
  end
end

# Consumer classes inherit from Karafka::BaseConsumer so they MUST load after
# `require "karafka"`. boot.rb eager-loads models/handlers/channels only.
Dir[File.expand_path('app/consumers/**/*.rb', __dir__)].sort.each { |f| require f }

# -----------------------------------------------------------------------------
# Karafka application
# -----------------------------------------------------------------------------
class NotifierApp < Karafka::App
  setup do |config|
    security_protocol = ENV.fetch('KAFKA_SECURITY_PROTOCOL', 'PLAINTEXT')
    kafka_config = {
      "bootstrap.servers": ENV.fetch('KAFKA_BROKERS', 'kafka:9092'),
      "client.id": 'ehs-notifier',
      "auto.offset.reset": 'earliest',
      "security.protocol": security_protocol
    }
    if security_protocol.include?('SASL')
      kafka_config[:"sasl.mechanisms"] = ENV.fetch('KAFKA_SASL_MECHANISM', 'SCRAM-SHA-512')
      kafka_config[:"sasl.username"]   = ENV.fetch('KAFKA_SASL_USERNAME')
      kafka_config[:"sasl.password"]   = ENV.fetch('KAFKA_SASL_PASSWORD')
    end
    kafka_config[:"ssl.ca.location"] = ENV.fetch('KAFKA_TLS_CA_FILE') if ENV['KAFKA_TLS_CA_FILE']
    config.kafka = kafka_config
    config.client_id = 'ehs-notifier'
    config.logger = Logger.new($stdout)
    # Our topic names mix dots and underscores (corrective_actions.v1, users.v1)
    # which Karafka 2.4+ flags by default. The producer side and topic registry
    # are already set with this convention, so we relax the check.
    config.strict_topics_namespacing = false
  end

  routes.draw do
    # Deserializers in Karafka 2.4+ are configured per-topic. Same Avro
    # decoder for every topic; the schema is looked up by ID embedded in
    # the Confluent wire header.
    avro = AvroDeserializer.new

    consumer_group :domain_events do
      topic 'incidents.v1' do
        consumer IncidentsConsumer
        deserializers payload: avro
      end
      topic 'corrective_actions.v1' do
        consumer CorrectiveActionsConsumer
        deserializers payload: avro
      end
      topic 'system.v1' do
        consumer SystemConsumer
        deserializers payload: avro
      end
    end

    consumer_group :reference_data do
      # Log-compacted — start from beginning so we rebuild users_mirror on cold start
      topic 'users.v1' do
        consumer UsersConsumer
        deserializers payload: avro
      end
    end
  end
end
