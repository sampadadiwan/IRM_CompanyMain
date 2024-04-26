namespace :db do  desc "Backup database to AWS-S3"


    task :backup => [:environment] do
      puts "Backing up db to S3"
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
      puts "Created backup: tmp/#{backup_filename}"
  
      # save to aws-s3
      bucket_name = "#{Rails.env}-db-backup.caphive.com" #gotcha: bucket names are unique across AWS-S3
      
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

    desc 'Test the latest database backup from S3'
    task :test_backup do

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
  
      # Connect to the local MySQL server
      DB = Mysql2::Client.new(
        host: Rails.application.credentials[:DB_HOST],
        username: Rails.application.credentials[:DB_USER],
        password: Rails.application.credentials[:DB_PASS]
      )    
      

      # Drop and recreate the test database
      DB.query('DROP DATABASE IF EXISTS test_db_restore')
      DB.query('CREATE DATABASE test_db_restore')
      DB.query('USE test_db_restore')
      puts "Dropped and recreated test database"

      # Restore the backup to the local MySQL database
      file_size = File.size(unzipped_file)

      puts "Loading backup #{human_readable_size(file_size)}, to test database. Please be patient ....."
      `mysql -u#{Rails.application.credentials[:DB_USER]} -p#{Rails.application.credentials[:DB_PASS]} -h#{Rails.application.credentials[:DB_HOST]} test_db_restore < #{unzipped_file}`
      puts "Restored backup to test database"


      # Run a query on the restored database
      result = DB.query('SELECT COUNT(*) FROM users')
  
      # Send an email if the query returns 0 rows
      if result.first['COUNT(*)'] == 0
        puts "Test failed: restored database has no users"
        e = StandardError.new "Test failed: restored database has no users"
        ExceptionNotifier.notify_exception(e)
        raise e
      else
        puts "Test passed: restored database has users"
      end
  
      # Clean up the temporary files
      File.delete(temp_file)
      File.delete(unzipped_file)
    end


    def human_readable_size(size)
      units = %w{B KB MB GB TB}
      e = (Math.log(size) / Math.log(1024)).floor
      s = "%.1f" % (size.to_f / 1024**e)
      s.sub(/\.?0*$/, '') + units[e]
    end

end
  
  # USAGE
  # =====
  # rake db:backup
  #
  # REQUIREMENT
  # ===========
  # gem: aws-sdk
  #
  # CREDITS
  # =======
  # http://www.rubyinside.com/amazon-official-aws-sdk-for-ruby-developers-5132.html