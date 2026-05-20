# frozen_string_literal: true

require 'json'
require 'sequel'

module Notifier
  module Web
    # Bridges Postgres LISTEN/NOTIFY into the in-process WsServer.
    #
    # The notifier runs as two processes sharing one image: the Karafka consumer
    # writes delivery_log rows; the Falcon web process holds the live WebSocket
    # sessions. Because the two processes share no memory, the consumer cannot
    # call WsServer.push directly. Channels::InAppChannel emits a Postgres NOTIFY
    # on `delivery_log_appended`; the web process subscribes here and re-pushes
    # the payload to any matching live sessions.
    #
    # Failures (connection drops, malformed payloads) are logged and the loop
    # reconnects with a short backoff. The WS-reconnect replay path
    # (`DeliveryLog.recent_unread_for`) remains the safety net for dropped
    # notifies.
    module PgListener
      CHANNEL = 'delivery_log_appended'
      BACKOFFS = [1, 5, 15].freeze

      def self.start!
        return if @started

        @started = true
        @thread = Thread.new { run_loop }
        @thread.name = 'pg-listener' if @thread.respond_to?(:name=)
      end

      def self.run_loop
        attempt = 0
        loop do
          listener_db = nil
          begin
            listener_db = Sequel.connect(ENV.fetch('DATABASE_URL'), max_connections: 1)
            attempt = 0
            listener_db.listen(CHANNEL, loop: true) do |_chan, _pid, raw|
              handle(raw)
            end
          rescue StandardError => e
            delay = BACKOFFS[[attempt, BACKOFFS.length - 1].min]
            attempt += 1
            warn "[pg_listener] reconnecting in #{delay}s after #{e.class}: #{e.message}"
            sleep delay
          ensure
            listener_db&.disconnect
          end
        end
      end

      def self.handle(raw)
        data = JSON.parse(raw, symbolize_names: true)
        WsServer.push(data[:user_id], data[:log])
      rescue StandardError => e
        warn "[pg_listener] bad payload: #{e.class}: #{e.message}"
      end
    end
  end
end
