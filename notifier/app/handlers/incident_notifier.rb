module Handlers
  # Common notification fanout flow:
  #   1. resolve recipient_user_ids against users_mirror (joins, drops missing)
  #   2. per recipient: check channel prefs, dedup via delivery_log (idempotent by event_id × user × channel),
  #      dispatch through each enabled channel
  module IncidentNotifier
    module_function

    def notify(event:, title:, body:, link_path:)
      event_id   = event.fetch("event_id")
      event_type = event.fetch("event_type")

      # Skip self-notifications: the user who triggered the action already
      # knows about it. actor_id is a stringified user_id from EventBus, or
      # the literal "system" for background jobs — the string-compare is
      # safe in both cases.
      recipient_ids = (event["recipient_user_ids"] || []) - [event["actor_id"]].compact
      recipients    = Notifier::Models::UserMirror.where(user_id: recipient_ids).all

      recipients.each do |user|
        prefs = (user.prefs || {})[event_type] || default_prefs

        deliver(:email,    user, event_id, event_type, title, body, link_path) if prefs["email"]
        deliver(:telegram, user, event_id, event_type, title, body, link_path) if prefs["telegram"] && user.telegram_chat_id
        deliver(:in_app,   user, event_id, event_type, title, body, link_path) if prefs["in_app"]
      end
    end

    def deliver(channel, user, event_id, event_type, title, body, link_path)
      log = Notifier::Models::DeliveryLog.claim(
        event_id:   event_id,
        user_id:    user.user_id,
        channel:    channel,
        event_type: event_type,
        title:      title,
        body:       body,
        link:       link_path
      )
      return unless log   # already delivered (idempotent)

      Channels.const_get(channel.to_s.split("_").map(&:capitalize).join + "Channel")
              .deliver(user: user, log: log)
    end

    def default_prefs
      { "email" => true, "telegram" => false, "in_app" => true }
    end
  end
end
