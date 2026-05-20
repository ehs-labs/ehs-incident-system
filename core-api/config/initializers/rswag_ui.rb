return unless Rails.env.development?

Rswag::Ui.configure do |c|
  c.openapi_endpoint "/api-docs/openapi.yaml", "EHS Incident System API v1"
end
