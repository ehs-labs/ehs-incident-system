module Channels
  module InAppChannel
    module_function

    # Persists the notification (DeliveryLog row already exists) and, when the
    # WS server module is loaded in the same process, pushes via active sessions.
    # The Karafka consumer process runs without the web app loaded — it just
    # writes the row; the web process picks it up via `recent_unread_for` when
    # a client connects (or via the LISTEN/NOTIFY bridge once that lands).
    def deliver(user:, log:)
      if defined?(Notifier::Web::WsServer)
        Notifier::Web::WsServer.push(user.user_id, log.values)
      end
      log.mark_sent!(:in_app)
    rescue StandardError => e
      log.mark_failed!(:in_app, e.message)
      raise
    end
  end
end
