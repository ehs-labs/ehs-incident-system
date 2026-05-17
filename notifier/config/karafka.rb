require_relative "boot"
require "karafka"
require "avro_turf/messaging"

# -----------------------------------------------------------------------------
# Avro deserializer — resolves schemas by ID from Karapace.
# -----------------------------------------------------------------------------
AVRO_MESSAGING = AvroTurf::Messaging.new(
  registry_url: ENV.fetch("KARAPACE_URL", "http://karapace:8081"),
  schemas_path: File.expand_path("../../schemas/events/v1", __dir__),
  namespace:    "com.ehs.events.v1"
)

class AvroDeserializer
  def call(message)
    AVRO_MESSAGING.decode(message.raw_payload)
  end
end

# -----------------------------------------------------------------------------
# Karafka application
# -----------------------------------------------------------------------------
class NotifierApp < Karafka::App
  setup do |config|
    config.kafka = {
      "bootstrap.servers" => ENV.fetch("KAFKA_BROKERS", "kafka:9092"),
      "client.id"         => "ehs-notifier",
      "auto.offset.reset" => "earliest"
    }
    config.client_id = "ehs-notifier"
    config.deserializer = AvroDeserializer.new
  end

  routes.draw do
    consumer_group :domain_events do
      topic "incidents.v1"          do consumer IncidentsConsumer end
      topic "corrective_actions.v1" do consumer CorrectiveActionsConsumer end
      topic "system.v1"             do consumer SystemConsumer end
    end

    consumer_group :reference_data do
      topic "users.v1" do
        consumer UsersConsumer
        # Log-compacted — start from beginning so we rebuild the mirror on cold start
      end
    end
  end
end
