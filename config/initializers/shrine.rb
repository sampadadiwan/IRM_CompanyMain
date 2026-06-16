require "shrine"
require "shrine/storage/file_system"
require "shrine/storage/memory"
require "shrine/storage/s3"

case Rails.configuration.upload_server
when :s3, :s3_multipart
  require "shrine/storage/s3"

  # Note AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY will no longer be set, the EC2 instance will use IAM roles for this.
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

  # In parallel test runs each process gets its own sub-directory so that the
  # AfterAll hook can clean up only its own files without racing against other
  # still-running processes that share the same public/uploads/ tree.
  upload_prefix = if Rails.env.test?
                    n = ENV.fetch('TEST_ENV_NUMBER', 'test')
                    "uploads/#{n}"
                  else
                    "uploads"
                  end

  # both `cache` and `store` storages are needed
  Shrine.storages = {
    cache: Shrine::Storage::FileSystem.new("public", prefix: "#{upload_prefix}/cache"),
    store: Shrine::Storage::FileSystem.new("public", prefix: upload_prefix)
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
