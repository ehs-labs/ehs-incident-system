module Handlers
  # Routes a decoded domain event to the per-event-type handler.
  # The handler decides recipients (via users_mirror), renders templates,
  # and fans out to channels.
  module DomainEvent
    HANDLERS = {} # event_type => handler proc

    module_function

    def register(event_type, handler = nil, &block)
      HANDLERS[event_type] = handler || block
    end

    def dispatch(event)
      handler = HANDLERS[event.fetch("event_type")]
      return unless handler   # silently skip unrecognized — analytics consumers will care, we don't

      handler.call(event)
    end

    # Resolve actor_id -> human name via users_mirror so notification bodies
    # read like "Wendy Worker reported ..." rather than referring to ids.
    # Falls back to "System" for the literal "system" actor (background jobs)
    # and to "Someone" when the actor row hasn't propagated yet.
    def actor_name(event)
      actor_id = event["actor_id"]
      return "System" if actor_id.nil? || actor_id.to_s == "system"
      Notifier::Models::UserMirror[user_id: actor_id.to_s]&.name || "Someone"
    end
  end
end

# ---- Register handlers -------------------------------------------------------

Handlers::DomainEvent.register("IncidentSubmitted") do |event|
  incident_id = event.dig("subject", "incident_id")
  Handlers::IncidentNotifier.notify(
    event:     event,
    title:     "Incident ##{incident_id} submitted",
    body:      "#{Handlers::DomainEvent.actor_name(event)} reported a new incident at severity #{event.dig('subject', 'severity')}: #{event.dig('subject', 'summary')}",
    link_path: "/incidents/#{incident_id}"
  )
end

Handlers::DomainEvent.register("IncidentAssigned") do |event|
  incident_id = event.dig("subject", "incident_id")
  Handlers::IncidentNotifier.notify(
    event:     event,
    title:     "Incident ##{incident_id} assigned to you",
    body:      "#{Handlers::DomainEvent.actor_name(event)} assigned incident ##{incident_id} (severity #{event.dig('subject', 'severity')}) to you to investigate.",
    link_path: "/incidents/#{incident_id}"
  )
end

Handlers::DomainEvent.register("IncidentClosed") do |event|
  incident_id = event.dig("subject", "incident_id")
  Handlers::IncidentNotifier.notify(
    event:     event,
    title:     "Incident ##{incident_id} closed",
    body:      "Your incident ##{incident_id} (severity #{event.dig('subject', 'severity')}) has been resolved and closed by #{Handlers::DomainEvent.actor_name(event)}.",
    link_path: "/incidents/#{incident_id}"
  )
end

Handlers::DomainEvent.register("CorrectiveActionAssigned") do |event|
  incident_id = event.dig("subject", "incident_id")
  Handlers::IncidentNotifier.notify(
    event:     event,
    title:     "Corrective action assigned to you",
    body:      "#{Handlers::DomainEvent.actor_name(event)} assigned you a corrective action on incident ##{incident_id}: \"#{event.dig('subject', 'title')}\" (due #{event.dig('subject', 'due_date')}).",
    link_path: "/incidents/#{incident_id}"
  )
end

Handlers::DomainEvent.register("CorrectiveActionOverdue") do |event|
  incident_id = event.dig("subject", "incident_id")
  days = event.dig("subject", "days_overdue")
  Handlers::IncidentNotifier.notify(
    event:     event,
    title:     "Corrective action overdue",
    body:      "A corrective action on incident ##{incident_id} is #{days} day#{days == 1 ? '' : 's'} past its due date.",
    link_path: "/incidents/#{incident_id}"
  )
end

Handlers::DomainEvent.register("SlaBreached") do |event|
  incident_id = event.dig("subject", "incident_id")
  Handlers::IncidentNotifier.notify(
    event:     event,
    title:     "Incident ##{incident_id} breached its #{event.dig('subject', 'sla_kind').downcase} SLA",
    body:      "Incident ##{incident_id} (severity #{event.dig('subject', 'severity')}) is past its #{event.dig('subject', 'sla_kind').downcase} SLA window and still needs action.",
    link_path: "/incidents/#{incident_id}"
  )
end
