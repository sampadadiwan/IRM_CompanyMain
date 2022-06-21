require "shrine"
require "shrine/storage/file_system"
require "shrine/storage/memory"
if Rails.env.test?
  Shrine.storages = {
    cache: Shrine::Storage::Memory.new,
    store: Shrine::Storage::Memory.new
  }
else
  require "shrine/storage/s3"

  s3_options = {
    bucket: "#{ENV['AWS_S3_BUCKET']}.#{Rails.env}", # required
    region: (ENV['AWS_S3_REGION']).to_s, # required
    access_key_id: (ENV['AWS_ACCESS_KEY_ID']).to_s,
    secret_access_key: (ENV['AWS_SECRET_ACCESS_KEY']).to_s
  }

  Shrine.storages = {
    cache: Shrine::Storage::S3.new(prefix: "cache", **s3_options), # temporary
    store: Shrine::Storage::S3.new(**s3_options) # permanent
  }

end
Shrine.plugin :activerecord # loads Active Record integration
Shrine.plugin :cached_attachment_data # enables retaining cached file across form redisplays
Shrine.plugin :restore_cached_data  # extracts metadata for assigned cached files
Shrine.plugin :validation_helpers
Shrine.plugin :validation
Shrine.plugin :determine_mime_type, analyzer: :marcel
