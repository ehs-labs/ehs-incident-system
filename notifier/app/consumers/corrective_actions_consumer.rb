class CorrectiveActionsConsumer < Karafka::BaseConsumer
  def consume
    messages.each do |message|
      event = message.payload

      # Malformed historical messages can lack event_id (idempotency key for
      # DeliveryLog). Skip with a warning rather than retry-forever.
      unless event.is_a?(Hash) && event["event_id"]
        Karafka.logger.warn("[CorrectiveActionsConsumer] skipping malformed message offset=#{message.offset} (keys=#{event.is_a?(Hash) ? event.keys.inspect : event.class})")
        next
      end

      Handlers::DomainEvent.dispatch(event)
    rescue StandardError => e
      Karafka.logger.error("[CorrectiveActionsConsumer] error for #{event&.dig('event_id')}: #{e.class}: #{e.message}")
      Karafka.logger.error(e.backtrace.first(8).join("\n"))
      raise
    end
  end
end
