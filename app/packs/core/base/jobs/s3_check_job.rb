class S3CheckJob < ApplicationJob
  # S3 cross-region replication typically completes within this window; skip files
  # newer than this to avoid false alarms while replication is still in progress.
  REPLICATION_GRACE_PERIOD = 15.minutes

  # env_name (e.g. production.in / production.us): lets this run locally against
  # a specific deployment's AWS account, exactly as DbBackupFreshnessJob#perform
  # does. On the deployed server Capistrano symlinks the regional credentials
  # file, so the hourly cron keeps calling this with no argument and resolves
  # correctly; from a laptop, Rails.application.credentials is whatever the
  # default (development) credentials hold — a DIFFERENT account — so the DR
  # verification entry point s3:check_latest_file must pass env_name.
  def perform(env_name: nil)
    @env_name = env_name
    client = Aws::S3::Client.new(
      access_key_id: credentials[:AWS_ACCESS_KEY_ID],
      secret_access_key: credentials[:AWS_SECRET_ACCESS_KEY],
      region: ENV.fetch('AWS_S3_REGION', nil)
    )

    source_s3 = Aws::S3::Resource.new(client:)

    # Get the latest file from the source bucket
    source_bucket_name = ENV.fetch('AWS_S3_BUCKET', nil).to_s
    Rails.logger.debug { "Checking for the latest file in the source bucket #{source_bucket_name} in region #{ENV.fetch('AWS_S3_REGION', nil)}" }

    source_bucket = source_s3.bucket(source_bucket_name)
    source_objects = source_bucket.objects
    source_latest_file = source_objects.max_by(&:last_modified)
    Rails.logger.debug { "Latest file found: #{source_latest_file.key}" }

    # Prefer S3's own replication_status (set via the x-amz-replication-status header,
    # exposed by the SDK on head_object) over guessing from a clock: it tells us
    # definitively whether replication is done, still pending, or failed, instead of a
    # fixed time window that can both false-alarm (replication slower than the window)
    # and false-negative (file no longer the latest by the next run, so never re-checked).
    # `source_latest_file` is an Aws::S3::ObjectSummary (from bucket.objects), which has no
    # replication_status of its own — it only comes from a HeadObject call, so we fetch the
    # full Aws::S3::Object resource (which lazily calls head_object) to read it.
    replication_status = source_bucket.object(source_latest_file.key).replication_status
    case replication_status
    when "COMPLETED"
      # Already replicated — proceed to verify it landed in the destination bucket.
    when "PENDING"
      Rails.logger.debug { "Skipping check for '#{source_latest_file.key}', replication_status is PENDING." }
      return
    when "FAILED"
      msg = "S3 replication FAILED for '#{source_latest_file.key}' according to replication_status."
      Rails.logger.debug msg
      ExceptionNotifier.notify_exception(StandardError.new(msg), data: { file_key: source_latest_file.key })
      return
    else
      # No replication_status available (e.g. object not covered by a replication rule, or
      # the SDK/provider doesn't surface it) — fall back to the time-based heuristic.
      if source_latest_file.last_modified > Time.current - REPLICATION_GRACE_PERIOD
        Rails.logger.debug { "Skipping check for '#{source_latest_file.key}', it was modified too recently to have replicated yet." }
        return
      end
    end

    # S3 client for the destination bucket
    client = Aws::S3::Client.new(
      access_key_id: credentials[:AWS_ACCESS_KEY_ID],
      secret_access_key: credentials[:AWS_SECRET_ACCESS_KEY],
      region: ENV.fetch('AWS_S3_REPLICA_REGION', nil)
    )

    destination_s3 = Aws::S3::Resource.new(client:)
    # Check if the latest file from the source bucket has replicated to the destination bucket
    destination_bucket_name = ENV.fetch("AWS_S3_BUCKET_REPLICA", nil).to_s
    Rails.logger.debug { "Checking whether '#{source_latest_file.key}' exists in the destination bucket #{destination_bucket_name} in region #{ENV.fetch('AWS_S3_REPLICA_REGION', nil)}" }

    destination_bucket = destination_s3.bucket(destination_bucket_name)
    destination_object = destination_bucket.object(source_latest_file.key)

    if destination_object.exists?
      Rails.logger.debug { "The latest file '#{source_latest_file.key}' is present in the destination bucket." }
    else
      msg = "The latest file '#{source_latest_file.key}' is not present in the destination bucket."
      Rails.logger.debug msg
      e = StandardError.new msg
      ExceptionNotifier.notify_exception(e, data: {
        source_bucket: source_bucket_name,
        destination_bucket: destination_bucket_name,
        source_region: ENV.fetch('AWS_S3_REGION', nil),
        destination_region: ENV.fetch('AWS_S3_REPLICA_REGION', nil),
        file_key: source_latest_file.key,
        source_last_modified: source_latest_file.last_modified
      })
    end
  end

  private

  # Mirrors DbBackupFreshnessJob#credentials.
  def credentials
    @credentials ||= if @env_name
                       key_path = Rails.root.join("config", "credentials", "#{@env_name}.key")
                       raise "Key file not found for environment '#{@env_name}' at #{key_path}" unless File.exist?(key_path)

                       Rails.application.encrypted(
                         Rails.root.join("config", "credentials", "#{@env_name}.yml.enc"),
                         key_path: key_path
                       )
                     else
                       Rails.application.credentials
                     end
  end
end
