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