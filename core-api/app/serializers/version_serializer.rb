# Wraps a PaperTrail::Version with the audit-trail shape the API exposes.
# The whodunnit string is resolved to a User by the controller and passed
# in via params[:whodunnit_user]; the serializer just formats the row.
class VersionSerializer
  include JSONAPI::Serializer

  set_type :version
  set_id   :id

  attributes :event, :created_at

  attribute :whodunnit_user do |version, params|
    user = params[:users]&.dig(version.whodunnit)
    next nil unless user
    { id: user.id, email: user.email, name: user.name }
  end

  attribute :changes, &:changeset
end
