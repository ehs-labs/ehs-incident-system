class CommentSerializer
  include JSONAPI::Serializer

  set_type :comment
  attributes :body, :created_at, :updated_at

  attribute :incident_id
  attribute :author_id

  belongs_to :incident
  belongs_to :author, serializer: :user, record_type: :user
end
