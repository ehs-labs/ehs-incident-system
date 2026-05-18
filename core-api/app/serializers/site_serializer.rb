class SiteSerializer
  include JSONAPI::Serializer
  set_type :site
  attributes :name, :timezone, :organization_id, :created_at
end
