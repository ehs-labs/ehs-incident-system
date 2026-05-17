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
  end
end

# ---- Register handlers -------------------------------------------------------

Handlers::DomainEvent.register("IncidentSubmitted") do |event|
  Handlers::IncidentNotifier.notify(
    event:     event,
    title:     "Incident #{event.dig('subject', 'incident_id')} submitted",
    body:      "Severity #{event.dig('subject', 'severity')}: #{event.dig('subject', 'summary')}",
    link_path: "/incidents/#{event.dig('subject', 'incident_id')}"
  )
end

Handlers::DomainEvent.register("IncidentAssigned") do |event|
  Handlers::IncidentNotifier.notify(
    event:     event,
    title:     "Incident assigned to you",
    body:      "You have been assigned to investigate incident #{event.dig('subject', 'incident_id')} (severity #{event.dig('subject', 'severity')}).",
    link_path: "/incidents/#{event.dig('subject', 'incident_id')}"
  )
end

Handlers::DomainEvent.register("CorrectiveActionAssigned") do |event|
  Handlers::IncidentNotifier.notify(
    event:     event,
    title:     "Corrective action assigned",
    body:      "Due by #{event.dig('subject', 'due_date')}: #{event.dig('subject', 'title')}",
    link_path: "/actions/#{event.dig('subject', 'action_id')}"
  )
end

Handlers::DomainEvent.register("CorrectiveActionOverdue") do |event|
  Handlers::IncidentNotifier.notify(
    event:     event,
    title:     "Corrective action overdue",
    body:      "Action is #{event.dig('subject', 'days_overdue')} day(s) past due.",
    link_path: "/actions/#{event.dig('subject', 'action_id')}"
  )
end

Handlers::DomainEvent.register("SlaBreached") do |event|
  Handlers::IncidentNotifier.notify(
    event:     event,
    title:     "SLA breached",
    body:      "Incident #{event.dig('subject', 'incident_id')} (severity #{event.dig('subject', 'severity')}) breached its #{event.dig('subject', 'sla_kind').downcase} SLA.",
    link_path: "/incidents/#{event.dig('subject', 'incident_id')}"
  )
end
