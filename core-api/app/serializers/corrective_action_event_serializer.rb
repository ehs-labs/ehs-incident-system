class CorrectiveActionEventSerializer
  include JSONAPI::Serializer

  set_type :corrective_action_event
  attributes :event_name, :note, :actor_id, :created_at
end
