class AssignableUserSerializer
  include JSONAPI::Serializer

  set_type :user
  attributes :name, :email, :role
end
