class CorrectiveActionSerializer
  include JSONAPI::Serializer

  set_type :corrective_action
  attributes :title, :description, :state, :due_date,
             :completed_at, :verified_at,
             :created_at, :updated_at

  attribute :incident_id
  attribute :assignee_id
  attribute :created_by_id

  attribute :overdue, &:overdue?

  attribute :evidence_blob_ids do |action|
    action.evidence.map { |att| att.blob.id.to_s }
  end

  belongs_to :incident
  belongs_to :assignee,   serializer: :user, record_type: :user
  belongs_to :created_by, serializer: :user, record_type: :user
end
