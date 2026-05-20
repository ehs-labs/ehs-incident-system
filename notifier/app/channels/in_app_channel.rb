# frozen_string_literal: true

module Channels
  module InAppChannel
    module_function

    # Persists the notification (DeliveryLog row already exists) and pushes the
    # payload to any live WebSocket sessions for the user.
    #
    # The notifier runs as two processes sharing one image: the Karafka consumer
    # (no web app loaded) and the Falcon web server (sessions live here). The
    # in-process branch covers the case where deliver is called inside the web
    # process; the NOTIFY emits regardless so the OTHER process can pick it up
    # via PgListener.
    def deliver(user:, log:)
      Notifier::Web::WsServer.push(user.user_id, log.values) if defined?(Notifier::Web::WsServer)

      payload = JSON.generate(user_id: user.user_id, log: log.values)
      DB.notify(:delivery_log_appended, payload: payload)

      log.mark_sent!(:in_app)
    rescue StandardError => e
      log.mark_failed!(:in_app, e.message)
      raise
    end
  end
end
