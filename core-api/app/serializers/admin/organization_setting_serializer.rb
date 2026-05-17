module Admin
  class OrganizationSettingSerializer
    include JSONAPI::Serializer

    set_type :organization_setting
    attributes :sla_overrides, :organization_id, :created_at, :updated_at
  end
end
