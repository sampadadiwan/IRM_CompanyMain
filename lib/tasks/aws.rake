# Rakefile
require 'aws-sdk-ec2'
require 'rake'
require_relative 'aws_utils'

include AwsUtils

namespace :aws do  

  task :setup_infra, [:stack, :web_server_name, :db_server_name, :region] => [:environment] do |t, args|
    args.with_defaults(region: ENV["AWS_REGION"])
    setup_infra(args[:stack], args[:web_server_name], args[:db_server_name], args[:region])
  end

  task :get_latest_ami, [:name_tag, :region] => [:environment] do |t, args|
    args.with_defaults(region: ENV["AWS_REGION"])
    latest_ami = latest_ami(args[:name_tag], args[:region])
  end

  desc "Copy an AMI to a different region"
  task :copy_ami, [:ami_id, :destination_region] => [:environment] do |t, args|
    args.with_defaults(destination_region: ENV["AWS_BACKUP_REGION"]) # Default destination region
    copy_ami(args[:ami_id], args[:destination_region])
  end

  desc "Create an AMI and copy it to another region"
  task :create_and_copy_ami, [:instance_name, :destination_region] => [:environment] do |t, args|
    args.with_defaults(destination_region: ENV["AWS_BACKUP_REGION"])
    # Create an AMI from the instance name
    puts "Creating and copying AMI: #{args}"
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
end
