module Notifier
  module Web
    # Tracks live WebSocket sessions per user so the in-app channel can push
    # notifications. One user may have multiple sessions (multi-tab).
    module WsServer
      @sessions = {}   # user_id => Set<connection>
      @mutex = Mutex.new

      def self.handle(ws, user_id:)
        register(user_id, ws)

        # Send initial hello + last 20 unread notifications
        ws.write({ type: "connected", server_time: Time.now.utc.iso8601 }.to_json)
        Notifier::Models::DeliveryLog.recent_unread_for(user_id, limit: 20).each do |row|
          ws.write({ type: "notification", payload: row.to_h }.to_json)
        end

        # Read loop — accept pings, ignore everything else
        while (message = ws.read)
          begin
            data = JSON.parse(message.buffer)
            ws.write({ type: "pong" }.to_json) if data["type"] == "ping"
          rescue JSON::ParserError
            # ignore malformed client frames
          end
        end
      ensure
        unregister(user_id, ws)
      end

      def self.push(user_id, payload)
        @mutex.synchronize do
          (@sessions[user_id] || []).each do |ws|
            ws.write({ type: "notification", payload: payload }.to_json)
          rescue StandardError
            # caller will eventually unregister on read failure
          end
        end
      end

      def self.register(user_id, ws)
        @mutex.synchronize do
          @sessions[user_id] ||= []
          @sessions[user_id] << ws
        end
      end

      def self.unregister(user_id, ws)
        @mutex.synchronize do
          @sessions[user_id]&.delete(ws)
          @sessions.delete(user_id) if @sessions[user_id]&.empty?
        end
      end
    end
  end
end
