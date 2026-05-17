module Channels
  module InAppChannel
    module_function

    # Pushes via active WebSocket sessions for the user.
    # Persistence (so re-connecting clients can replay) happens in DeliveryLog.
    def deliver(user:, log:)
      Notifier::Web::WsServer.push(user.user_id, log.to_h)
      log.mark_sent!(:in_app)
    rescue StandardError => e
      log.mark_failed!(:in_app, e.message)
      raise
    end
  end
end
