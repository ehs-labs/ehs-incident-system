module Notifier
  module Models
    class DeliveryLog < Sequel::Model(:delivery_log)
      plugin :timestamps, update_on_create: true

      # Idempotent claim: returns the row if this is the first attempt for
      # (event_id, user_id, channel); returns nil if already delivered or pending.
      def self.claim(event_id:, user_id:, channel:, event_type:, title:, body:, link:)
        existing = where(event_id: event_id, user_id: user_id, channel: channel.to_s).first
        return nil if existing && existing.state != "failed"

        if existing
          existing.update(state: "pending", attempt_count: existing.attempt_count + 1)
          existing
        else
          create(
            event_id:      event_id,
            user_id:       user_id,
            channel:       channel.to_s,
            event_type:    event_type,
            title:         title,
            body:          body,
            link:          link,
            state:         "pending",
            attempt_count: 1
          )
        end
      end

      def mark_sent!(_channel)
        update(state: "sent", sent_at: Time.now.utc)
      end

      def mark_failed!(_channel, error_message)
        update(state: "failed", last_error: error_message, failed_at: Time.now.utc)
      end

      def self.recent_unread_for(user_id, limit: 20)
        where(user_id: user_id, channel: "in_app")
          .where(read_at: nil)
          .order(Sequel.desc(:created_at))
          .limit(limit)
      end
    end
  end
end
