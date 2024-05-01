namespace :db do  desc "Backup database to AWS-S3"

  def human_readable_size(size)
    units = %w{B KB MB GB TB}
    e = (Math.log(size) / Math.log(1024)).floor
    s = "%.1f" % (size.to_f / 1024**e)
    s.sub(/\.?0*$/, '') + units[e]
  end


  def restore_db(test_count_query: "SELECT COUNT(*) FROM users", restore_db_name: "test_db_restore", host: "localhost", port: 3306)
    puts "Testing latest backup from S3 for IRM_#{Rails.env}"
    client = Aws::S3::Client.new(
      :access_key_id => Rails.application.credentials[:AWS_ACCESS_KEY_ID],
      :secret_access_key => Rails.application.credentials[:AWS_SECRET_ACCESS_KEY],
      region: 'ap-south-1'
    )
    
    s3 = Aws::S3::Resource.new(client: client)

    
    # Get the latest backup file from the S3 bucket      
    bucket_name = "#{Rails.env}-db-backup.caphive.com"
    puts "Checking for latest backup in bucket #{bucket_name}"
    bucket = s3.bucket(bucket_name)
    objects = bucket.objects()
    latest_backup = objects.max_by(&:last_modified)
    puts "Latest backup found: #{latest_backup.key}"

    # Download the latest backup file to a temporary location
    temp_file = '/tmp/latest_backup.sql.gz'
    latest_backup.get(response_target: temp_file)


    # Gunzip the backup file
    unzipped_file = '/tmp/latest_backup.sql'
    Zlib::GzipReader.open(temp_file) do |gz|
      File.open(unzipped_file, 'wb') do |out|
        out.write gz.read
      end
    end
    puts "Downloaded and unzipped backup to #{unzipped_file}"

    puts "Connecting to #{host} on port #{port}"
    # Connect to the local MySQL server
    database = Mysql2::Client.new(
      host: host,
      username: Rails.application.credentials[:DB_USER],
      password: Rails.application.credentials[:DB_PASS],
      port: port
    )    
    
    # Drop and recreate the test database
    database.query("DROP DATABASE IF EXISTS #{restore_db_name}")
    database.query("CREATE DATABASE #{restore_db_name}")
    database.query("USE #{restore_db_name}")
    puts "Dropped and recreated #{restore_db_name}"

    # Restore the backup to the local MySQL database
    file_size = File.size(unzipped_file)

    puts "Loading backup #{human_readable_size(file_size)}, to #{restore_db_name}. Please be patient ....."
    
    cmd = "pv #{unzipped_file} | mysql -u#{Rails.application.credentials[:DB_USER]} -p#{Rails.application.credentials[:DB_PASS]} -h#{host} -P #{port} #{restore_db_name}"
    puts cmd
    `#{cmd}`

    puts "Restored backup to #{restore_db_name}"

    # Run a query on the restored database
    result = database.query(test_count_query)

    # Send an email if the query returns 0 rows
    if result.first['COUNT(*)'] == 0
      puts "Test failed: restored database has no users"
      e = StandardError.new "Test failed: restored database has no users"
      ExceptionNotifier.notify_exception(e)
      # raise e
    else
      puts "Test passed: restored database #{restore_db_name} has users"
    end

    # Clean up the temporary files
    File.delete(temp_file)
    File.delete(unzipped_file)
  end

  def backup_db
    puts "Backing up IRM_#{Rails.env} to S3"
    datestamp = Time.now.strftime("%Y-%m-%d_%H-%M-%S")
    backup_filename = "#{Rails.root.basename}-#{datestamp}.sql"
    db_config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env)

    # process backup
    `mysqldump -u #{Rails.application.credentials[:DB_USER]} -p#{Rails.application.credentials[:DB_PASS]} -h#{Rails.application.credentials[:DB_HOST]} -i -c -q --single-transaction --lock-tables=false IRM_#{Rails.env} > tmp/#{backup_filename}`

    size_kb = File.size("tmp/#{backup_filename}").to_f / 1024

    if size_kb < 10
      e = StandardError.new "mysqldump created file which is too small, backup aborted"
      ExceptionNotifier.notify_exception(e)
      raise e
    end

    `gzip -9 tmp/#{backup_filename}`
    puts "Created backup: tmp/#{backup_filename} of size #{human_readable_size(size_kb)}"

    # save to aws-s3
    bucket_name = "#{AWS_S3_BUCKET}.db-backup" #gotcha: bucket names are unique across AWS-S3
    
    client = Aws::S3::Client.new(
      :access_key_id => Rails.application.credentials[:AWS_ACCESS_KEY_ID],
      :secret_access_key => Rails.application.credentials[:AWS_SECRET_ACCESS_KEY],
      region: 'ap-south-1'
    )
    
    s3 = Aws::S3::Resource.new(client: client)

    bucket = s3.buckets.find{|b| b.name == bucket_name}

    unless bucket
      puts "\n Creating bucket #{bucket_name}"
      bucket = s3.create_bucket({
        acl: "private", # accepts private, public-read, public-read-write, authenticated-read
        bucket: bucket_name,
        create_bucket_configuration: {
          location_constraint: "ap-south-1", # accepts EU, eu-west-1, us-west-1, us-west-2, ap-south-1, ap-southeast-1, ap-southeast-2, ap-northeast-1, sa-east-1, cn-north-1, eu-central-1
        },
      })
    end

    puts "Uploading tmp/#{backup_filename}.gz to S3 bucket #{bucket_name}"
    object = s3.bucket(bucket_name).object("#{backup_filename}.gz")
    object.upload_file("tmp/#{backup_filename}.gz")
    puts "Upload completed successfully"
    # remove local backup file
    `rm -f tmp/#{backup_filename}.gz`

    # Removing old backups
    puts "Deleting old backups"
    bucket.objects.each do |obj|
      if (obj.last_modified < (Date.today - 1.weeks))
        puts "Deleting DB backup from S3: #{obj.key}"
        obj.delete
      end
    end
  end

  task :backup => [:environment] do
    # We touch a user, so that the backup has a timestamp. This will be used to test the restored database
    User.support_users.first.touch
    backup_db
  end

  desc 'Test the latest database backup from S3'
  task :restore, [:restore_db_name, :db_host] do |t, args|
    
    args.with_defaults(:restore_db_name => :test_db_restore)
    puts "\n#####################"
    puts "Restoring latest backup from S3 for IRM_#{Rails.env} to #{args[:restore_db_name]} on #{args[:db_host]}"
    puts "#######################"

    restore_db_name = args[:restore_db_name]

    host = args[:db_host] == "Primary" ? Rails.application.credentials[:DB_HOST] : Rails.application.credentials[:DB_HOST_REPLICA]

    puts "Restoring latest backup from S3 for IRM_#{Rails.env} to #{restore_db_name} on #{host}"
    restore_db(restore_db_name:, host:)      
  end

  task :backup_and_test => [:environment] do
    # We touch a user, so that the backup has a timestamp. This will be used to test the restored database
    time = Time.zone.now
    u = User.support_users.first
    u.update_column(:updated_at, time)

    # Backup the DB
    backup_db

    # Restore the DB
    restore_db(test_count_query: "SELECT COUNT(*) FROM users where updated_at = '#{time.strftime("%Y-%m-%d %H:%M:%S.%6N")}'")
  end

  desc 'Create a MySQL replica on a different machine'
  task :create_replica, [:skip_restore_backup] do |t, args|

    args.with_defaults(:skip_restore_backup => false)
    skip_restore_backup = args[:skip_restore_backup]

    # Connection details for the source database
    source_host = Rails.application.credentials[:DB_HOST]
    source_user = Rails.application.credentials[:DB_USER]
    source_password = Rails.application.credentials[:DB_PASS]
    source_database = "IRM_#{Rails.env}"
    source_port = 3306

    # Connection details for the destination database
    destination_host = Rails.application.credentials[:DB_HOST_REPLICA]
    destination_user = Rails.application.credentials[:DB_USER]
    destination_password = Rails.application.credentials[:DB_PASS]
    destination_database = "IRM_#{Rails.env}"
    destination_port = 3306

    puts "\n#####################"
    puts "Creating a MySQL replica on #{destination_host} for database #{destination_database}"
    puts "#######################"

    # Connect to the source database
    source_client = Mysql2::Client.new(
      host: source_host,
      username: source_user,
      password: source_password,
      database: source_database,
      port: source_port
    )

    # Connect to the destination database
    destination_client = Mysql2::Client.new(
      host: destination_host,
      username: destination_user,
      password: destination_password,
      port: destination_port
    )

    # Get the current binary log file and position from the source
    result = source_client.query('SHOW MASTER STATUS')
    binlog_file = result.first['File']
    binlog_position = result.first['Position']
    puts "Current binary log file: #{binlog_file}, position: #{binlog_position}"

    # Create a new database on the destination
    destination_client.query("CREATE DATABASE IF NOT EXISTS #{destination_database}")

    restore_db(restore_db_name: destination_database, host: destination_host, port: destination_port) unless skip_restore_backup
    
    # Set up replication on the destination
    change_master_query = "CHANGE MASTER TO
      MASTER_HOST='#{source_host}',
      MASTER_USER='#{source_user}',
      MASTER_PORT=#{source_port},
      MASTER_PASSWORD='#{source_password}',
      MASTER_LOG_FILE='#{binlog_file}',
      MASTER_LOG_POS=#{binlog_position}"

    puts "Setting up replication on the destination with query: #{change_master_query}"
    # This is to make the slave different from the master
    destination_client.query('SET GLOBAL server_id = 2')
    # Stop and reset the replica
    destination_client.query('STOP REPLICA')
    destination_client.query('RESET REPLICA ALL')
    # Setup the replica
    destination_client.query(change_master_query)
    # Start the replica
    puts 'Starting slave replication on the destination'
    destination_client.query('START REPLICA')
    puts 'Replication setup complete!'

    source_client.query('SHOW REPLICA STATUS')
  end
  
end
