# Rakefile
require 'dotenv'
require 'aws-sdk-ec2'
require 'net/http'
require 'uri'
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
  task :setup_infra, [:stack, :web_server_name, :db_server_name, :region, :env_variant, :env_name] do |t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
    args.with_defaults(region: ENV["AWS_REGION"])
    setup_infra(args[:stack], args[:web_server_name], args[:db_server_name], args[:region], args[:env_variant])
  end

  task :get_latest_ami, [:name_tag, :region, :env_name] do |t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
    args.with_defaults(region: ENV["AWS_REGION"])
    latest_ami = latest_ami(args[:name_tag], args[:region])
  end

  desc "Copy an AMI to a different region"
  task :copy_ami, [:ami_id, :destination_region, :env_name] do |t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
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
  task :create_and_copy_ami, [:instance_name, :destination_region, :env_name] do |t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
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
  task :delete_old_amis, [:name_tag, :region, :env_name] do |t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
    args.with_defaults(region: ENV["AWS_REGION"])
    cleanup_amis(args[:name_tag], args[:region])
  end

  desc "Create an AMI from a named EC2 instance"
  task :create_ami, [:instance_name, :env_name] do |t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
    create_ami_from_snapshot(args)
  end

  task :environment, [:env_name] do |t, args|

    unless ENV["AWS_ACCESS_KEY_ID"].present? && ENV["AWS_SECRET_ACCESS_KEY"].present?
      puts "################################################################################"
      puts "⚠️  AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY not set in environment variables."
      puts "################################################################################"
      raise "⚠️  AWS keys must be set in environment variables"
    end

    env_name = args[:env_name]

    if env_name
      env_file = ".env.#{env_name}"
      if File.exist?(env_file)
        Dotenv.overload(env_file)
        puts "✅ Overloaded environment variables from #{env_file}"
      else
        puts "⚠️  Environment file not found: #{env_file}"
      end
    end

    credentials = if env_name
                    key_path = Rails.root.join("config", "credentials", "#{env_name}.key")
                    unless File.exist?(key_path)
                      raise "Key file not found for environment '#{env_name}' at #{key_path}"
                    end
                    Rails.application.encrypted(
                      Rails.root.join("config", "credentials", "#{env_name}.yml.enc"),
                      key_path: key_path
                    )
                  else
                    Rails.application.credentials
                  end

    puts "🔑 Configuring AWS SDK for region #{ENV['AWS_REGION']}, using ENV for AWS keys"
    Aws.config.update({
      region: ENV["AWS_REGION"],
      access_key_id: ENV["AWS_ACCESS_KEY_ID"],
      secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
    })
  end


  desc "Provision and replicate S3 buckets"
  task :provision_s3_buckets, [:env_name] do |t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
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
  desc "Generate Prometheus configuration (prometheus.yml) with EC2 instance IPs"
  task :generate_prometheus_yml, [:env_name] do |t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
    require "yaml"

    ec2 = Aws::EC2::Client.new

    def fetch_instance_ips(ec2, filters)
      resp = ec2.describe_instances(filters: filters)
      resp.reservations.flat_map do |res|
        res.instances.map(&:private_ip_address).compact
      end
    end

    app_ips = fetch_instance_ips(ec2, [{ name: "tag:Name", values: ["AppServer"] }])
    db_ips  = fetch_instance_ips(ec2, [{ name: "tag:Name", values: ["DB-Redis-ES"] }])

    puts "📝 Generating Prometheus config with the following IPs:"
    puts "📦 App Server IPs: #{app_ips.join(", ")}"
    puts "📦 DB Server IPs: #{db_ips.join(", ")}"

    prometheus_config = {
      "global" => { "scrape_interval" => "15s" },
      "scrape_configs" => [
        {
          "job_name" => "rails_app",
          "static_configs" => [
            { "targets" => app_ips.map { |ip| "#{ip}:9394" } }
          ]
        },
        {
          "job_name" => "node",
          "static_configs" => [
            { "targets" => (app_ips + db_ips).uniq.map { |ip| "#{ip}:9100" } }
          ]
        },
        {
          "job_name" => "db_server",
          "static_configs" => [
            { "targets" => db_ips.flat_map { |ip| ["#{ip}:9104", "#{ip}:9114", "#{ip}:9121"] } }
          ]
        }
      ]
    }

    output_path = "config/initializers/observability/prometheus.yml"
    FileUtils.mkdir_p(File.dirname(output_path))
    require "yaml"

    # Building formatted YAML content manually for clarity and conventions
    yaml_lines = []
    yaml_lines << "global:"
    yaml_lines << "  scrape_interval: 15s  # How frequently to scrape targets (default is every 15s)"
    yaml_lines << ""
    yaml_lines << "scrape_configs:"

    rails_app_targets = app_ips.map { |ip| "'#{ip}:9394'" }.join(', ')
    node_targets = (app_ips + db_ips).uniq.map { |ip| "'#{ip}:9100'" }.join(', ')
    db_server_targets = db_ips.flat_map { |ip| ["'#{ip}:9104'", "'#{ip}:9114'", "'#{ip}:9121'"] }.join(', ')

    yaml_lines << "  - job_name: 'rails_app'"
    yaml_lines << "    static_configs:"
    yaml_lines << "      - targets: [#{rails_app_targets}]"
    yaml_lines << ""
    yaml_lines << "  - job_name: 'node'"
    yaml_lines << "    static_configs:"
    yaml_lines << "      - targets: [#{node_targets}]"
    yaml_lines << ""
    yaml_lines << "  - job_name: 'db_server'"
    yaml_lines << "    static_configs:"
    yaml_lines << "      - targets: [#{db_server_targets}]"

    formatted_yaml = yaml_lines.join("\n") + "\n"

    File.open(output_path, "w") do |f|
      f.puts "# Prometheus Configuration File"
      f.puts "# Generated automatically via rake aws:generate_prometheus_yml"
      f.puts "#"
      f.puts "# Port Reference:"
      f.puts "# 9394  - Rails Prometheus Exporter"
      f.puts "# 9100  - Node Exporter"
      f.puts "# 9104  - MySQL Exporter"
      f.puts "# 9114  - Elasticsearch Exporter"
      f.puts "# 9121  - Redis Exporter"
      f.puts "#"
      f.puts "# EC2 Instance Mapping:"
      f.puts "# AppServer IPs: #{app_ips.join(', ')}"
      f.puts "# DB_Redis_ES IPs: #{db_ips.join(', ')}"
      f.puts ""
      f.puts formatted_yaml
    end

    puts "✅ Generated annotated Prometheus config file at #{output_path}"
  end

  desc "Find and optionally delete unused security groups"
  task :cleanup_unused_security_groups, [:env_name] do |t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
    ec2 = Aws::EC2::Client.new(region: Aws.config[:region])
    puts "🔍 Fetching all security groups..."
    all_groups = ec2.describe_security_groups.security_groups

    used_group_ids = []
    puts "🔍 Collecting in-use security groups from network interfaces..."
    ec2.describe_network_interfaces.network_interfaces.each do |ni|
      used_group_ids.concat(ni.groups.map(&:group_id))
    end

    used_group_ids.uniq!
    unused = all_groups.reject do |sg|
      used_group_ids.include?(sg.group_id) || sg.group_name == "default"
    end

    if unused.empty?
      puts "✅ No unused security groups found."
      next
    end

    puts "⚠️  Found the following unused security groups:"
    unused.each do |sg|
      puts "- #{sg.group_id} (#{sg.group_name})"
    end

    print "❓ Do you want to delete these security groups? (y/N): "
    confirm = $stdin.gets.chomp
    if confirm.downcase == "y"
      unused.each do |sg|
        begin
          ec2.delete_security_group(group_id: sg.group_id)
          puts "🗑️  Deleted #{sg.group_id} (#{sg.group_name})"
        rescue Aws::EC2::Errors::DependencyViolation => e
          puts "⚠️  Could not delete #{sg.group_id} (in use or dependency violation)"
        end
      end
      puts "✅ Cleanup complete."
    else
      puts "❎ Cleanup aborted by user."
    end
  end

  desc "Find and optionally delete unused VPCs and subnets"
  task :cleanup_unused_vpcs_and_subnets, [:env_name] do |t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
    ec2 = Aws::EC2::Client.new(region: Aws.config[:region])

    # --- Find Unused Subnets ---
    puts "🔍 Fetching all subnets and network interfaces..."
    all_subnets = ec2.describe_subnets.subnets
    all_network_interfaces = ec2.describe_network_interfaces.network_interfaces
    used_subnet_ids = all_network_interfaces.map(&:subnet_id).uniq
    unused_subnets = all_subnets.reject { |s| used_subnet_ids.include?(s.subnet_id) }

    # --- Find Unused VPCs ---
    puts "🔍 Fetching all VPCs..."
    all_vpcs = ec2.describe_vpcs.vpcs.reject(&:is_default)
    # A VPC is considered in use if it has any network interfaces associated with it.
    # This is a strong indicator of active resources (instances, LBs, etc.).
    used_vpc_ids = all_network_interfaces.map(&:vpc_id).uniq
    unused_vpcs = all_vpcs.reject { |v| used_vpc_ids.include?(v.vpc_id) }

    if unused_subnets.empty? && unused_vpcs.empty?
      puts "✅ No unused subnets or VPCs found."
      next
    end

    puts "⚠️  Found the following unused resources:"
    unused_subnets.each do |s|
      subnet_name = s.tags.find { |t| t.key == "Name" }&.value || "N/A"
      puts "- Subnet: #{s.subnet_id} (Name: #{subnet_name}, VPC: #{s.vpc_id}, CIDR: #{s.cidr_block})"
    end
    unused_vpcs.each do |v|
      vpc_name = v.tags.find { |t| t.key == "Name" }&.value || "N/A"
      puts "- VPC: #{v.vpc_id} (Name: #{vpc_name}, CIDR: #{v.cidr_block})"
    end

    print "❓ Do you want to delete these resources? (y/N): "
    confirm = $stdin.gets.chomp
    if confirm.downcase == "y"
      # Delete subnets first
      unused_subnets.each do |s|
        begin
          ec2.delete_subnet(subnet_id: s.subnet_id)
          puts "🗑️  Deleted Subnet #{s.subnet_id}"
        rescue => e
          puts "⚠️  Could not delete Subnet #{s.subnet_id}: #{e.message}"
        end
      end

      # Then delete VPCs
      unused_vpcs.each do |v|
        begin
          ec2.delete_vpc(vpc_id: v.vpc_id)
          puts "🗑️  Deleted VPC #{v.vpc_id}"
        rescue Aws::EC2::Errors::DependencyViolation => e
          puts "⚠️  Could not delete VPC #{v.vpc_id}. It may still have dependencies (like Internet Gateways or Route Tables) that must be removed manually."
        rescue => e
          puts "⚠️  Could not delete VPC #{v.vpc_id}: #{e.message}"
        end
      end
      puts "✅ Cleanup complete."
    else
      puts "❎ Cleanup aborted by user."
    end
  end
  def find_groups_with_open_port(ec2_client, port)
    open_groups = []
    ec2_client.describe_security_groups.security_groups.each do |sg|
      sg.ip_permissions.each do |perm|
        next unless perm.from_port == port && perm.to_port == port && perm.ip_protocol == "tcp"

        if perm.ip_ranges.any? { |range| range.cidr_ip == "0.0.0.0/0" }
          open_groups << { id: sg.group_id, name: sg.group_name }
          break
        end
      end
    end
    open_groups
  end

  desc "Manage SSH access (port 22). Actions: list, suspend, resume. Use force=true for non-interactive mode. ex: bundle exec rake 'aws:manage_ssh[suspend,staging.in,true]'"
  task :manage_ssh, [:action, :env_name, :force] do |t, args|
    # Manually invoke the environment task with the provided env_name
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])

    action = args[:action] || "list"
    puts "🔑 Managing SSH access with action: #{action} for region #{ENV['AWS_REGION']}"
    ec2 = Aws::EC2::Client.new()

    case action
    when "list"
      puts "🔍 Finding security groups with SSH (port 22) open to 0.0.0.0/0..."
      open_groups = find_groups_with_open_port(ec2, 22)

      if open_groups.empty?
        puts "✅ No security groups with unrestricted SSH access found."
      else
        puts "⚠️  Found the following security groups with open SSH access:"
        open_groups.each do |sg|
          puts "- #{sg[:id]} (#{sg[:name]})"
        end
      end

    when "suspend"
      puts "🔍 Finding security groups with SSH open to suspend..."
      open_groups = find_groups_with_open_port(ec2, 22)

      if open_groups.empty?
        puts "✅ No security groups with unrestricted SSH access to suspend."
        next
      end

      puts "⚠️  The following security groups have SSH open to the world:"
      open_groups.each { |sg| puts "- #{sg[:id]} (#{sg[:name]})" }

      force = args[:force].to_s.downcase == 'true'
      confirmed = if force
                    true
                  else
                    print "❓ Do you want to suspend SSH access (move to port 22222) for these groups? (y/N): "
                    $stdin.gets.chomp.downcase == "y"
                  end

      if confirmed
        open_groups.each do |sg|
          begin
            ec2.revoke_security_group_ingress(group_id: sg[:id], ip_permissions: [{ ip_protocol: "tcp", from_port: 22, to_port: 22, ip_ranges: [{ cidr_ip: "0.0.0.0/0" }] }])
            ec2.authorize_security_group_ingress(group_id: sg[:id], ip_permissions: [{ ip_protocol: "tcp", from_port: 22222, to_port: 22222, ip_ranges: [{ cidr_ip: "0.0.0.0/0" }] }])
            puts "🔒 Suspended SSH for #{sg[:id]} (#{sg[:name]})"
          rescue => e
            puts "❌ Failed to suspend SSH for #{sg[:id]}: #{e.message}"
          end
        end
        puts "✅ SSH suspension complete."
      else
        puts "❎ Aborted by user."
      end

    when "resume"
      puts "🔍 Finding security groups with suspended SSH to resume..."
      suspended_groups = find_groups_with_open_port(ec2, 22222)

      if suspended_groups.empty?
        puts "✅ No security groups with suspended SSH access found."
        next
      end

      puts "⚠️  The following security groups have suspended SSH access (on port 22222):"
      suspended_groups.each { |sg| puts "- #{sg[:id]} (#{sg[:name]})" }

      force = args[:force].to_s.downcase == 'true'
      confirmed = if force
                    true
                  else
                    print "❓ Do you want to resume SSH access (move back to port 22) for these groups? (y/N): "
                    $stdin.gets.chomp.downcase == "y"
                  end

      if confirmed
        suspended_groups.each do |sg|
          begin
            ec2.revoke_security_group_ingress(group_id: sg[:id], ip_permissions: [{ ip_protocol: "tcp", from_port: 22222, to_port: 22222, ip_ranges: [{ cidr_ip: "0.0.0.0/0" }] }])
            ec2.authorize_security_group_ingress(group_id: sg[:id], ip_permissions: [{ ip_protocol: "tcp", from_port: 22, to_port: 22, ip_ranges: [{ cidr_ip: "0.0.0.0/0" }] }])
            puts "🔓 Resumed SSH for #{sg[:id]} (#{sg[:name]})"
          rescue => e
            puts "❌ Failed to resume SSH for #{sg[:id]}: #{e.message}"
          end
        end
        puts "✅ SSH resumption complete."
      else
        puts "❎ Aborted by user."
      end
    else
      puts "❌ Invalid action '#{action}'. Available actions: list, suspend, resume."
    end
  end
end