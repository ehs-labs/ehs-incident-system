class IncidentSerializer
  include JSONAPI::Serializer

  set_type :incident
  attributes :state, :incident_type, :severity, :occurred_at, :location,
             :summary, :description, :root_cause,
             :submitted_at, :triaged_at, :closed_at, :sla_breached_at,
             :created_at, :updated_at

  attribute :site_id
  attribute :reporter_id
  attribute :assignee_id
  attribute :organization_id

  attribute :triage_overdue, &:triage_overdue?
  attribute :triage_deadline, &:triage_deadline

  belongs_to :site
  belongs_to :reporter, serializer: :user, record_type: :user
  belongs_to :assignee, serializer: :user, record_type: :user
end
