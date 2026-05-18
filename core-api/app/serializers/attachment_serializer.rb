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

  # Relative path to the ActiveStorage *proxy* endpoint. Proxy mode streams
  # the blob through Rails instead of 302-redirecting to a presigned MinIO
  # URL — important in local dev because the MinIO endpoint configured in
  # storage.yml ("http://minio:9000") is only resolvable inside the docker
  # network. With proxy mode the browser only talks to core-api.
  #
  # In prod (real S3) you'd want to flip this to `rails_blob_path` so
  # downloads stream straight from S3 and don't hit Rails — that's a single
  # line swap and an env flag.
  attribute(:url) do |a|
    Rails.application.routes.url_helpers.rails_storage_proxy_path(a.blob, only_path: true)
  end
end
