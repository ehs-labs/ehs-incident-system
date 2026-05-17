class IncidentsConsumer < Karafka::BaseConsumer
  def consume
    messages.each do |message|
      event = message.payload   # already Avro-decoded by AvroDeserializer
      Handlers::DomainEvent.dispatch(event)
    rescue StandardError => e
      logger.error("IncidentsConsumer error for #{event&.dig('event_id')}: #{e.class} #{e.message}")
      raise   # let Karafka apply the configured retry/DLQ strategy
    end
  end
end
