class WitnessSerializer
  include JSONAPI::Serializer

  set_type :witness
  attributes :name, :email, :phone, :statement, :created_at, :updated_at

  attribute :incident_id

  belongs_to :incident
end
