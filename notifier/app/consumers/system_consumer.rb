# frozen_string_literal: true

class SystemConsumer < Karafka::BaseConsumer
  def consume
    messages.each do |message|
      Handlers::DomainEvent.dispatch(message.payload)
    end
  end
end
