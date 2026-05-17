class UserSerializer
  include JSONAPI::Serializer

  set_type :user
  attributes :name, :email, :role
  attribute :organization_id
  attribute :confirmed_at
  attribute :locked_at
  attribute :deleted, &:deleted?
end
