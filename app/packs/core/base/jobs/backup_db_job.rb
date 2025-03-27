class BackupDbJob < ApplicationJob
  def perform(action = "backup")
    Chewy.strategy(:atomic) do
      case action
      when "backup"
        # We touch a user, so that the backup has a timestamp. This will be used to test the restored database
        User.support_users.first.touch

        # Backup the primary DB
        backup_db

        # At 2 am once only
        if Time.zone.now.hour == 2
          # Restore the backup to the replica and check if the restore was successful
          restore_db(host: Rails.application.credentials[:DB_HOST_REPLICA], delete_after_restore: true)
        end
      when "restore"
        # We restore the backup to the replica. In the future we should have a separate machine for testing the backup
        restore_db(host: Rails.application.credentials[:DB_HOST_REPLICA], delete_after_restore: true)
      end
    end
  end

  def human_readable_size(size)
    units = %w[B KB MB GB TB]
    e = (Math.log(size) / Math.log(1024)).floor
    s = format("%.1f", (size.to_f / (1024**e)))
    s.sub(/\.?0*$/, '') + units[e]
  end

  # The backup is generally 1 hr old, so we check for 90 minutes
  BACKUP_DURATION = 90

  def restore_db(test_count_query: nil, restore_db_name: "test_db_restore", host: nil, port: nil, delete_after_restore: false)
    # The backup is generally 1 hr old, so we check for 90 minutes
    time_utc = (Time.zone.now - BACKUP_DURATION.minutes).utc
    test_count_query ||= "SELECT COUNT(*) FROM users where updated_at > '#{time_utc}'"
    host ||= Rails.application.credentials[:DB_HOST_REPLICA]
    port ||= 3306

    if  host == Rails.application.credentials[:DB_HOST] &&
        restore_db_name == Rails.application.credentials[:DB_NAME]
      msg = "Cannot restore the primary database to itself"
      error_msg = { from: "BackupDbJob", status: "Failed", msg: msg }
      EntityMailer.with(error_msg: error_msg, subject: "Error in restore_db").notify_errors.deliver_now
      raise msg
    end

    Rails.logger.debug { "Testing latest backup from S3 for IRM_#{Rails.env}" }
    client = Aws::S3::Client.new(
      access_key_id: Rails.application.credentials[:AWS_ACCESS_KEY_ID],
      secret_access_key: Rails.application.credentials[:AWS_SECRET_ACCESS_KEY],
      region: ENV.fetch("AWS_S3_REGION", nil)
    )

    s3 = Aws::S3::Resource.new(client:)

    # Get the latest backup file from the S3 bucket
    # bucket_name = "#{Rails.env}-db-backup.caphive.com"
    bucket_name = "#{ENV.fetch('AWS_S3_BUCKET', nil)}.db-backup"
    Rails.logger.debug { "Checking for latest backup in bucket #{bucket_name}" }
    bucket = s3.bucket(bucket_name)
    objects = bucket.objects
    latest_backup = objects.max_by(&:last_modified)
    Rails.logger.debug { "Latest backup found: #{latest_backup.key}" }

    # Download the latest backup file to a temporary location
    temp_file = '/tmp/latest_backup.sql.gz'
    latest_backup.get(response_target: temp_file)

    # Gunzip the backup file
    unzipped_file = '/tmp/latest_backup.sql'
    Zlib::GzipReader.open(temp_file) do |gz|
      File.binwrite(unzipped_file, gz.read)
    end
    Rails.logger.debug { "Downloaded and unzipped backup to #{unzipped_file}" }

    Rails.logger.debug { "Connecting to #{host} on port #{port}" }
    # Connect to the local MySQL server
    database = Mysql2::Client.new(
      host:,
      username: Rails.application.credentials[:DB_USER],
      password: Rails.application.credentials[:DB_PASS],
      port:
    )

    # Drop and recreate the test database
    database.query("DROP DATABASE IF EXISTS #{restore_db_name}")
    database.query("CREATE DATABASE #{restore_db_name}")
    database.query("USE #{restore_db_name}")
    Rails.logger.debug { "Dropped and recreated #{restore_db_name}" }

    # Restore the backup to the local MySQL database
    file_size = File.size(unzipped_file)

    Rails.logger.debug { "Loading backup #{human_readable_size(file_size)}, to #{restore_db_name}. Please be patient ....." }

    cmd = "pv #{unzipped_file} | mysql -u#{Rails.application.credentials[:DB_USER]} -p#{Rails.application.credentials[:DB_PASS]} -h#{host} -P #{port} #{restore_db_name}"
    Rails.logger.debug cmd
    `#{cmd}`

    Rails.logger.debug { "Restored backup to #{restore_db_name}" }

    # Run a query on the restored database
    Rails.logger.debug { "Running test query #{test_count_query}" }
    Rails.logger.debug { "Checking for support user #{User.support_users.first.updated_at.utc}" }

    result = database.query(test_count_query)

    get_file_date_time(latest_backup.key)
    # Send an email if the query returns 0 rows
    if result.first['COUNT(*)'].zero?
      msg = "Restore Backup failed: #{latest_backup.key} restored database has no users updated in the last #{BACKUP_DURATION} mins"
      Rails.logger.debug msg
      error_msg = { from: "BackupDbJob", status: "Failed", msg: msg }
      # raise e
    else
      msg = "Restore Backup passed: #{latest_backup.key} restored database #{restore_db_name} has users updated in the last #{BACKUP_DURATION} mins"
      Rails.logger.debug msg
      error_msg = { from: "BackupDbJob", status: "Passed", msg: msg }
    end
    EntityMailer.with(error_msg: error_msg, subject: msg).notify_errors.deliver_now

    # Clean up the temporary files
    File.delete(temp_file)
    File.delete(unzipped_file)
    database.query("DROP DATABASE IF EXISTS #{restore_db_name}") if delete_after_restore
  end

  def get_file_date_time(file_name)
    match = file_name.match(/IRM-(\d{4}-\d{2}-\d{2})_(\d{2}-\d{2}-\d{2})/)
    if match
      date_str = match[1] # "2025-03-21"
      time_str = match[2] # "13-10-04"

      # Combine and parse to DateTime
      datetime_str = "#{date_str} #{time_str.tr('-', ':')}" # "2025-03-21 13:10:04"
      DateTime.parse(datetime_str)

    end
  end

  def backup_bd_full_xtrabackup; end

  def backup_bd_full_incremental_xtrabackup; end

  def backup_db
    Rails.logger.debug { "Backing up IRM_#{Rails.env} to S3" }
    datestamp = Time.zone.now.strftime("%Y-%m-%d_%H-%M-%S")
    backup_filename = "#{Rails.root.basename}-#{datestamp}.sql"
    ActiveRecord::Base.configurations.configs_for(env_name: Rails.env)

    # This is for the restore_db which checks if there are any users updated in the last 90 minutes
    User.joins(:roles).where(roles: { name: 'support' }).first.touch

    # process backup
    `mysqldump -u #{Rails.application.credentials[:DB_USER]} -p#{Rails.application.credentials[:DB_PASS]} -h#{Rails.application.credentials[:DB_HOST]} -i -c -q --single-transaction --lock-tables=false IRM_#{Rails.env} > tmp/#{backup_filename}`

    size_kb = File.size("tmp/#{backup_filename}").to_f / 1024

    if size_kb < 100
      msg = "mysqldump created file which is too small, backup aborted"
      error_msg = { from: "BackupDbJob", status: "Failed", msg: }
      EntityMailer.with(error_msg: error_msg, subject: "Error in backup_db").notify_errors.deliver_now
      raise msg
    end

    `gzip -9 tmp/#{backup_filename}`
    Rails.logger.debug { "Created backup: tmp/#{backup_filename} of size #{human_readable_size(size_kb)}" }

    # save to aws-s3
    # bucket_name = "#{Rails.env}-db-backup.caphive.com"
    bucket_name = "#{ENV.fetch('AWS_S3_BUCKET', nil)}.db-backup" # gotcha: bucket names are unique across AWS-S3

    client = Aws::S3::Client.new(
      access_key_id: Rails.application.credentials[:AWS_ACCESS_KEY_ID],
      secret_access_key: Rails.application.credentials[:AWS_SECRET_ACCESS_KEY],
      region: ENV.fetch("AWS_S3_REGION", nil)
    )

    s3 = Aws::S3::Resource.new(client:)

    bucket = s3.buckets.find { |b| b.name == bucket_name }

    unless bucket
      Rails.logger.debug { "\n Creating bucket #{bucket_name}" }
      s3.create_bucket({
                         acl: "private", # accepts private, public-read, public-read-write, authenticated-read
                         bucket: bucket_name,
                         create_bucket_configuration: {
                           location_constraint: ENV.fetch("AWS_S3_REGION", nil) # accepts EU, eu-west-1, us-west-1, us-west-2, ap-south-1, ap-southeast-1, ap-southeast-2, ap-northeast-1, sa-east-1, cn-north-1, eu-central-1
                         }
                       })
    end

    Rails.logger.debug { "Uploading tmp/#{backup_filename}.gz to S3 bucket #{bucket_name}" }
    object = s3.bucket(bucket_name).object("#{backup_filename}.gz")
    object.upload_file("tmp/#{backup_filename}.gz")
    Rails.logger.debug "Upload completed successfully"

    # Removing old backups - This is now handled by S3 bucket management rules
    # Rails.logger.debug "Deleting old backups"
    # bucket.objects.each do |obj|
    #   if obj.last_modified < (Time.zone.today - 1.week)
    #     Rails.logger.debug { "Deleting DB backup from S3: #{obj.key}" }
    #     obj.delete
    #   end
    # end
  rescue StandardError => e
    msg = "Error backing up database: #{e.message}"
    Rails.logger.error { e.backtrace.join("\n") }
    error_msg = { from: "BackupDbJob", status: "Failed", msg: }
    EntityMailer.with(error_msg: error_msg, subject: "Error in backup_db").notify_errors.deliver_now
    raise msg
  ensure
    # remove local backup file
    Rails.logger.debug "Removing local backup file"
    `rm -f tmp/#{backup_filename}.gz` if File.exist?("tmp/#{backup_filename}.gz")
  end
end
