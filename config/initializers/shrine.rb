require "shrine"
require "shrine/storage/file_system"
require "shrine/storage/memory"
require "shrine/storage/s3"

case Rails.configuration.upload_server
when :s3, :s3_multipart
  require "shrine/storage/s3"

  s3_options = {
    bucket: ENV.fetch('AWS_S3_BUCKET', nil).to_s, # required
    region: ENV.fetch('AWS_S3_REGION', nil).to_s, # required
    access_key_id: Rails.application.credentials[:AWS_ACCESS_KEY_ID].to_s,
    secret_access_key: Rails.application.credentials[:AWS_SECRET_ACCESS_KEY].to_s
  }

  # both `cache` and `store` storages are needed
  Shrine.storages = {
    cache: Shrine::Storage::S3.new(prefix: "cache", **s3_options),
    store: Shrine::Storage::S3.new(**s3_options)
  }
when :app
  require "shrine/storage/file_system"

  # both `cache` and `store` storages are needed
  Shrine.storages = {
    cache: Shrine::Storage::FileSystem.new("public", prefix: "uploads/cache"),
    store: Shrine::Storage::FileSystem.new("public", prefix: "uploads")
  }
end

Shrine.plugin :activerecord # loads Active Record integration
Shrine.plugin :cached_attachment_data # enables retaining cached file across form redisplays
Shrine.plugin :restore_cached_data # extracts metadata for assigned cached files
Shrine.plugin :validation_helpers
Shrine.plugin :validation
Shrine.plugin :keep_files unless Rails.env.local?
Shrine.plugin :determine_mime_type, analyzer: :marcel, analyzer_options: { filename_fallback: true }
Shrine.plugin :presign_endpoint
Shrine.plugin :upload_endpoint
Shrine.plugin :uppy_s3_multipart # load the plugin
# Shrine.plugin :instrumentation # adds instrumentation
Shrine.plugin :backgrounding # load the plugin globally

Shrine::Attacher.destroy_block do
  DestroyShrineJob.perform_later(self.class.name, data)
end
