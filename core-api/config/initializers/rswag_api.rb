return unless Rails.env.development?

Rswag::Api.configure do |c|
  c.openapi_root = Rails.root.to_s
end
