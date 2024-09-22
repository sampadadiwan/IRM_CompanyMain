class BackupDbJob < ApplicationJob
  def perform
    Chewy.strategy(:atomic) do
      # We touch a user, so that the backup has a timestamp. This will be used to test the restored database
      User.support_users.first.touch
      backup_db
    end
  end

  def human_readable_size(size)
    units = %w[B KB MB GB TB]
    e = (Math.log(size) / Math.log(1024)).floor
    s = format("%.1f", (size.to_f / (1024**e)))
    s.sub(/\.?0*$/, '') + units[e]
  end

  def restore_db(test_count_query: "SELECT COUNT(*) FROM users", restore_db_name: "test_db_restore", host: "localhost", port: 3306)
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
    result = database.query(test_count_query)

    # Send an email if the query returns 0 rows
    if result.first['COUNT(*)'].zero?
      Rails.logger.debug "Test failed: restored database has no users"
      e = StandardError.new "Test failed: restored database has no users"
      ExceptionNotifier.notify_exception(e)
      # raise e
    else
      Rails.logger.debug { "Test passed: restored database #{restore_db_name} has users" }
    end

    # Clean up the temporary files
    File.delete(temp_file)
    File.delete(unzipped_file)
  end

  def backup_bd_full_xtrabackup; end

  def backup_bd_full_incremental_xtrabackup; end

  def backup_db
    Rails.logger.debug { "Backing up IRM_#{Rails.env} to S3" }
    datestamp = Time.zone.now.strftime("%Y-%m-%d_%H-%M-%S")
    backup_filename = "#{Rails.root.basename}-#{datestamp}.sql"
    ActiveRecord::Base.configurations.configs_for(env_name: Rails.env)

    # process backup
    `mysqldump -u #{Rails.application.credentials[:DB_USER]} -p#{Rails.application.credentials[:DB_PASS]} -h#{Rails.application.credentials[:DB_HOST]} -i -c -q --single-transaction --lock-tables=false IRM_#{Rails.env} > tmp/#{backup_filename}`

    size_kb = File.size("tmp/#{backup_filename}").to_f / 1024

    if size_kb < 100
      e = StandardError.new "mysqldump created file which is too small, backup aborted"
      ExceptionNotifier.notify_exception(e)
      raise e
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
      bucket = s3.create_bucket({
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

    # Removing old backups
    Rails.logger.debug "Deleting old backups"
    bucket.objects.each do |obj|
      if obj.last_modified < (Time.zone.today - 1.week)
        Rails.logger.debug { "Deleting DB backup from S3: #{obj.key}" }
        obj.delete
      end
    end
  rescue StandardError => e
    Rails.logger.error { "Error backing up database: #{e.message}" }
    Rails.logger.error { e.backtrace.join("\n") }
    ExceptionNotifier.notify_exception(e, data: { message: "Error backing up database" })
  ensure
    # remove local backup file
    Rails.logger.debug "Removing local backup file"
    `rm -f tmp/#{backup_filename}.gz` if File.exist?("tmp/#{backup_filename}.gz")
  end
end
