module Admin
  class UserSerializer
    include JSONAPI::Serializer

    set_type :user
    attributes :name, :email, :role
    attribute :organization_id
    attribute :confirmed_at
    attribute :locked_at
    attribute :invitation_sent_at
    attribute :invitation_accepted_at
    attribute :deleted_at
    attribute :deleted, &:deleted?
    attribute :locked, &:access_locked?
  end
end
