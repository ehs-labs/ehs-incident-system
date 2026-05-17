class AttachmentSerializer
  include JSONAPI::Serializer

  set_type :attachment

  attribute(:filename)     { |a| a.blob.filename.to_s }
  attribute(:content_type) { |a| a.blob.content_type }
  attribute(:byte_size)    { |a| a.blob.byte_size }
  attribute(:checksum)     { |a| a.blob.checksum }
  attribute(:created_at)   { |a| a.blob.created_at }
  attribute(:incident_id)  { |a| a.record_id }
  attribute(:signed_id)    { |a| a.blob.signed_id }

  # Relative path to the ActiveStorage redirect endpoint. The frontend
  # prepends the API host; this avoids depending on default_url_options
  # which differs between dev, test, and prod.
  attribute(:signed_url) do |a|
    Rails.application.routes.url_helpers.rails_blob_path(a.blob, only_path: true)
  end
end
