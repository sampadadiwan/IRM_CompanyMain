require 'aws-sdk-s3'

namespace :s3 do
  desc 'Check if the latest file in the source bucket is present in the destination bucket'
  task :check_latest_file do
    # Configure AWS credentials and regions
    client = Aws::S3::Client.new(
        :access_key_id => Rails.application.credentials[:AWS_ACCESS_KEY_ID],
        :secret_access_key => Rails.application.credentials[:AWS_SECRET_ACCESS_KEY],
        region: 'ap-south-1' # Mumbai
    )
    
    source_s3 = Aws::S3::Resource.new(client: client)

    # Get the latest file from the source bucket
    source_bucket_name = "#{ENV["AWS_S3_BUCKET"]}.#{Rails.env}"
    puts "Checking for the latest file in the source bucket #{source_bucket_name}"

    source_bucket = source_s3.bucket(source_bucket_name)
    source_objects = source_bucket.objects()
    source_latest_file = source_objects.max_by(&:last_modified)
    puts "Latest file found: #{source_latest_file.key}"

    # S3 client for the destination bucket
    client = Aws::S3::Client.new(
        :access_key_id => Rails.application.credentials[:AWS_ACCESS_KEY_ID],
        :secret_access_key => Rails.application.credentials[:AWS_SECRET_ACCESS_KEY],
        region: 'ap-southeast-1' # Singapore
    )
    
    destination_s3 = Aws::S3::Resource.new(client: client)

    # Check if the latest file exists in the destination bucket
    destination_bucket_name = "#{ENV["AWS_S3_BUCKET_REPLICA"]}"

    destination_bucket = destination_s3.bucket(destination_bucket_name)
    destination_objects = destination_bucket.objects()
    destination_latest_file = destination_objects.max_by(&:last_modified)
    puts "Latest file found: #{destination_latest_file.key}"


    if destination_latest_file.key != source_latest_file.key
        msg = "The latest file '#{source_latest_file.key}' is not present in the destination bucket."
        puts msg
        e = StandardError.new msg
        ExceptionNotifier.notify_exception(e)
    else
      puts "The latest file '#{source_latest_file.key}' is present in the destination bucket."
    end
  end
end