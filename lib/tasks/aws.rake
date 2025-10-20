# Rakefile
require 'aws-sdk-ec2'
require 'rake'
require_relative 'aws_utils'

include AwsUtils

namespace :aws do

  task :grow_disk do
    # Run the following system cmds
    puts "🌱 Growing disk..."
    system("df -k /")
    system("sudo lsblk")
    system("sudo growpart /dev/nvme0n1 1")
    system("sudo lsblk")
    system("sudo resize2fs /dev/nvme0n1p1")
    system("df -k /")
    puts "✅ Disk grown successfully."
  end

  # This is the task that will be called whenever we need to do a complete DR into another region
  task :setup_infra, [:stack, :web_server_name, :db_server_name, :region, :env_variant] => [:environment] do |t, args|
    args.with_defaults(region: ENV["AWS_REGION"])
    setup_infra(args[:stack], args[:web_server_name], args[:db_server_name], args[:region], args[:env_variant])
  end

  task :get_latest_ami, [:name_tag, :region] => [:environment] do |t, args|
    args.with_defaults(region: ENV["AWS_REGION"])
    latest_ami = latest_ami(args[:name_tag], args[:region])
  end

  desc "Copy an AMI to a different region"
  task :copy_ami, [:ami_id, :destination_region] => [:environment] do |t, args|
    # Prioritize ami_id from args, then from environment variable
    ami_id = args[:ami_id] || ENV["ami_id"]
    destination_region = args[:destination_region] || ENV["AWS_BACKUP_REGION"] # Default destination region

    # Ensure ami_id is present
    unless ami_id
      raise "AMI ID is missing. Please provide it as an argument (e.g., rake aws:copy_ami[ami-xxxxxxxxxxxxxxxxx]) or as an environment variable (e.g., ami_id=ami-xxxxxxxxxxxxxxxxx rake aws:copy_ami)."
    end

    copy_ami(ami_id, destination_region)
  end

  desc "Create an AMI and copy it to another region"
  task :create_and_copy_ami, [:instance_name, :destination_region] => [:environment] do |t, args|
    args.with_defaults(destination_region: ENV["AWS_BACKUP_REGION"])

    # Create an AMI from the instance name
    puts "📦 Creating and copying AMI: #{args}"
    ami_id = create_ami_from_snapshot(args)
    # Copy the AMI to the destination region
    copy_ami(ami_id, args[:destination_region])
    # Clean up old AMIs
    cleanup_amis(args[:instance_name], Aws.config[:region])
    cleanup_amis(args[:instance_name], args[:destination_region])
  end


  desc "Delete old AMIs with the same name pattern"
  task :delete_old_amis, [:name_tag, :region] => [:environment] do |t, args|
    args.with_defaults(region: ENV["AWS_REGION"])
    cleanup_amis(args[:name_tag], args[:region])
  end

  desc "Create an AMI from a named EC2 instance"
  task :create_ami, [:instance_name] => [:environment] do |t, args|
    create_ami_from_snapshot(args)
  end

  task :environment do
    Aws.config.update({
      region: ENV["AWS_REGION"],
      :access_key_id => Rails.application.credentials[:AWS_ACCESS_KEY_ID],
      :secret_access_key => Rails.application.credentials[:AWS_SECRET_ACCESS_KEY],
      # Additional configuration like credentials could be added here
    })
  end


  desc "Provision and replicate S3 buckets"
  task provision_s3_buckets: :environment do
    require "aws-sdk-s3"

    source_bucket  = ENV.fetch("AWS_S3_BUCKET")
    db_backup_xtra_bucket = "#{source_bucket}-backup-xtra"
    replica_bucket = ENV.fetch("AWS_S3_BUCKET_REPLICA")
    replica_db_backup_xtra_bucket = "#{replica_bucket}-backup-xtra"

    # Allow source & replica to live in different regions
    source_region  = ENV.fetch("AWS_S3_REGION")                            # e.g., "us-east-1"
    replica_region = ENV.fetch("AWS_S3_REPLICA_REGION", source_region)     # e.g., "us-east-1"


    # Build per-region clients
    s3 = {
      source:  Aws::S3::Client.new(region: source_region),
      replica: Aws::S3::Client.new(region: replica_region),
      db_backup_xtra: Aws::S3::Client.new(region: source_region),
      replica_db_backup_xtra: Aws::S3::Client.new(region: replica_region)
    }

    def ensure_bucket!(client:, bucket:, region:)
      begin
        client.head_bucket(bucket: bucket)
        puts "✅ Bucket '#{bucket}' already exists in (client) region #{region}."
      rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchBucket
        # Create with correct us-east-1 handling
        if region == "us-east-1"
          client.create_bucket(bucket: bucket)
        else
          client.create_bucket(
            bucket: bucket,
            create_bucket_configuration: { location_constraint: region }
          )
        end
        puts "🪣 Created bucket '#{bucket}' in #{region}."
      rescue Aws::S3::Errors::Http301Error => e
        # Existing bucket but different region than client; show the actual region to fix envs
        actual = e.context.http_response.headers["x-amz-bucket-region"] rescue nil
        raise "Bucket '#{bucket}' exists in region '#{actual}'. Use a client in that region."
      end

      # Versioning is required for replication
      client.put_bucket_versioning(
        bucket: bucket,
        versioning_configuration: { status: "Enabled" }
      )
      puts "📜 Enabled versioning on '#{bucket}'."
    end

    # Ensure both buckets exist + versioning on
    ensure_bucket!(client: s3[:source],  bucket: source_bucket,  region: source_region)
    ensure_bucket!(client: s3[:replica], bucket: replica_bucket, region: replica_region)
    ensure_bucket!(client: s3[:db_backup_xtra], bucket: db_backup_xtra_bucket, region: source_region)
    ensure_bucket!(client: s3[:replica_db_backup_xtra], bucket: replica_db_backup_xtra_bucket, region: replica_region)

    puts "✅ Both buckets are provisioned and versioning enabled."
    puts "ℹ️  Note: CORS policies and other settings must be configured manually as needed."
    puts "⚠️  Warning: without proper CORS settings, web apps will face issues accessing the buckets."
    puts "ℹ️  Note: Replication must be setup manually"
    puts "⚠️  Warning: without replication setup, objects will not be auto-replicated between buckets."
  end
end