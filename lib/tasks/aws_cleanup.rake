namespace :aws do
  desc "Cleanup EBS snapshots older than X days (default 30). Use DRY_RUN=true to only list. Use RETENTION_DAYS=X to change retention. Usage: rake aws:cleanup_snapshots[env_name]"
  task :cleanup_snapshots, [:env_name] => :environment do |_t, args|
    # Invoke the environment setup task from aws.rake to load credentials and region
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])

    require 'aws-sdk-ec2'

    # The aws:environment task updates Aws.config, so we can just use the client
    # It will use the region from ENV['AWS_REGION'] and credentials from Rails credentials
    ec2 = Aws::EC2::Client.new

    retention_days = (ENV['RETENTION_DAYS'] || 30).to_i
    dry_run = ENV['DRY_RUN'] == 'true'
    cutoff_date = Time.now - (retention_days * 24 * 60 * 60)

    region = Aws.config[:region] || ENV['AWS_REGION'] || 'us-east-1'

    puts "🔍 Searching for snapshots in #{region} older than #{cutoff_date} (Retention: #{retention_days} days)..."
    puts "🚫 DRY RUN ENABLED. No snapshots will be deleted." if dry_run

    begin
      snapshots = ec2.describe_snapshots(owner_ids: ['self']).snapshots

      old_snapshots = snapshots.select { |s| s.start_time < cutoff_date }

      if old_snapshots.empty?
        puts "✅ No old snapshots found in #{region}."
      else
        puts "⚠️ Found #{old_snapshots.size} snapshots to delete in #{region}."

        old_snapshots.each do |snap|
          description = snap.description.presence || "No description"
          print "ID: #{snap.snapshot_id} | Created: #{snap.start_time} | #{description} "

          if dry_run
            puts "[SKIPPED - DRY RUN]"
          else
            begin
              ec2.delete_snapshot(snapshot_id: snap.snapshot_id)
              puts "✅ [DELETED]"
            rescue Aws::EC2::Errors::InvalidSnapshotInUse
              puts "❌ [SKIPPED - IN USE BY AMI]"
            rescue StandardError => e
              puts "❌ [ERROR: #{e.message}]"
            end
          end
        end
      end
    rescue StandardError => e
      puts "❌ Failed to fetch snapshots in #{region}: #{e.message}"
    end

    puts "🏁 Cleanup complete for #{region}."
  end

  desc "Release unassociated Elastic IPs. Use DRY_RUN=true to only list. Usage: rake aws:cleanup_elastic_ips[env_name]"
  task :cleanup_elastic_ips, [:env_name] => :environment do |_t, args|
    # Invoke the environment setup task from aws.rake to load credentials and region
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])

    require 'aws-sdk-ec2'

    ec2 = Aws::EC2::Client.new
    dry_run = ENV['DRY_RUN'] == 'true'
    region = Aws.config[:region] || ENV['AWS_REGION'] || 'us-east-1'

    puts "🔍 Searching for unassociated Elastic IPs in #{region}..."
    puts "🚫 DRY RUN ENABLED. No IPs will be released." if dry_run

    begin
      addresses = ec2.describe_addresses.addresses
      # Definitive logic: An IP is unassociated if it has no AssociationId
      # This covers both IPs with no ENI and IPs with an ENI that isn't attached to anything.
      unassociated_ips = addresses.select { |addr| addr.association_id.nil? }

      if unassociated_ips.empty?
        puts "✅ No unassociated Elastic IPs found in #{region}."
      else
        puts "⚠️ Found #{unassociated_ips.size} unassociated Elastic IPs to release in #{region}."

        unassociated_ips.each do |addr|
          print "IP: #{addr.public_ip} | Allocation ID: #{addr.allocation_id} "

          if dry_run
            puts "[SKIPPED - DRY RUN]"
          else
            begin
              ec2.release_address(allocation_id: addr.allocation_id)
              puts "✅ [RELEASED]"
            rescue StandardError => e
              puts "❌ [ERROR: #{e.message}]"
            end
          end
        end
      end
    rescue StandardError => e
      puts "❌ Failed to fetch Elastic IPs in #{region}: #{e.message}"
    end

    puts "🏁 Cleanup complete for #{region}."
  end

  desc "Delete unattached EBS volumes. Use DRY_RUN=true to only list. Usage: rake aws:cleanup_unattached_volumes[env_name]"
  task :cleanup_unattached_volumes, [:env_name] => :environment do |_t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
    require 'aws-sdk-ec2'
    ec2 = Aws::EC2::Client.new
    dry_run = ENV['DRY_RUN'] == 'true'
    region = Aws.config[:region] || ENV['AWS_REGION'] || 'us-east-1'

    puts "🔍 Searching for unattached EBS volumes in #{region}..."
    puts "🚫 DRY RUN ENABLED. No volumes will be deleted." if dry_run

    begin
      volumes = ec2.describe_volumes(filters: [{ name: 'status', values: ['available'] }]).volumes
      if volumes.empty?
        puts "✅ No unattached EBS volumes found in #{region}."
      else
        puts "⚠️ Found #{volumes.size} unattached EBS volumes to delete in #{region}."
        volumes.each do |vol|
          name = vol.tags.find { |t| t.key == 'Name' }&.value || "Unnamed"
          print "ID: #{vol.volume_id} | Size: #{vol.size}GB | Name: #{name} "
          if dry_run
            puts "[SKIPPED - DRY RUN]"
          else
            begin
              ec2.delete_volume(volume_id: vol.volume_id)
              puts "✅ [DELETED]"
            rescue StandardError => e
              puts "❌ [ERROR: #{e.message}]"
            end
          end
        end
      end
    rescue StandardError => e
      puts "❌ Failed to fetch volumes in #{region}: #{e.message}"
    end
    puts "🏁 Cleanup complete for #{region}."
  end

  desc "Terminate stopped EC2 instances. Use DRY_RUN=true to only list. Usage: rake aws:cleanup_stopped_instances[env_name]"
  task :cleanup_stopped_instances, [:env_name] => :environment do |_t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
    require 'aws-sdk-ec2'
    ec2 = Aws::EC2::Client.new
    dry_run = ENV['DRY_RUN'] == 'true'
    region = Aws.config[:region] || ENV['AWS_REGION'] || 'us-east-1'

    puts "🔍 Searching for stopped EC2 instances in #{region}..."
    puts "🚫 DRY RUN ENABLED. No instances will be terminated." if dry_run

    begin
      resp = ec2.describe_instances(filters: [{ name: 'instance-state-name', values: ['stopped'] }])
      instances = resp.reservations.flat_map(&:instances)

      if instances.empty?
        puts "✅ No stopped EC2 instances found in #{region}."
      else
        puts "⚠️ Found #{instances.size} stopped EC2 instances to terminate in #{region}."
        instances.each do |inst|
          name = inst.tags.find { |t| t.key == 'Name' }&.value || "Unnamed"
          print "ID: #{inst.instance_id} | Type: #{inst.instance_type} | Name: #{name} "
          if dry_run
            puts "[SKIPPED - DRY RUN]"
          else
            begin
              ec2.terminate_instances(instance_ids: [inst.instance_id])
              puts "✅ [TERMINATED]"
            rescue StandardError => e
              puts "❌ [ERROR: #{e.message}]"
            end
          end
        end
      end
    rescue StandardError => e
      puts "❌ Failed to fetch instances in #{region}: #{e.message}"
    end
    puts "🏁 Cleanup complete for #{region}."
  end

  desc "List NAT Gateways and check for redundancy. Usage: rake aws:list_nat_gateways[env_name]"
  task :list_nat_gateways, [:env_name] => :environment do |_t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
    require 'aws-sdk-ec2'
    ec2 = Aws::EC2::Client.new
    region = Aws.config[:region] || ENV['AWS_REGION'] || 'us-east-1'

    puts "🔍 Listing NAT Gateways in #{region}..."
    begin
      nats = ec2.describe_nat_gateways(filter: [{ name: 'state', values: ['available'] }]).nat_gateways
      if nats.empty?
        puts "✅ No active NAT Gateways found in #{region}."
      else
        puts "⚠️ Found #{nats.size} active NAT Gateways in #{region}:"
        nats.group_by(&:vpc_id).each do |vpc_id, vpc_nats|
          puts "VPC: #{vpc_id} has #{vpc_nats.size} NAT Gateway(s)."
          vpc_nats.each { |n| puts "  - ID: #{n.nat_gateway_id} | Subnet: #{n.subnet_id}" }
          puts "  💡 ADVICE: You have redundant NAT Gateways in this VPC. Consider deleting one to save ~$32/mo." if vpc_nats.size > 1
        end
      end
    rescue StandardError => e
      puts "❌ Failed to fetch NAT Gateways in #{region}: #{e.message}"
    end
  end

  desc "Setup S3 Glacier Lifecycle for backup buckets. Usage: rake aws:setup_s3_glacier[env_name]"
  task :setup_s3_glacier, [:env_name] => :environment do |_t, args|
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(args[:env_name])
    require 'aws-sdk-s3'
    s3 = Aws::S3::Client.new

    # Target buckets that look like backups
    puts "🔍 Searching for backup buckets to apply Glacier lifecycle..."
    begin
      buckets = s3.list_buckets.buckets
      backup_buckets = buckets.select { |b| b.name.include?('backup') || b.name.include?('xtra') }

      if backup_buckets.empty?
        puts "✅ No backup buckets found."
      else
        backup_buckets.each do |b|
          puts "📦 Applying 30-day Glacier transition to #{b.name}..."
          s3.put_bucket_lifecycle_configuration(
            bucket: b.name,
            lifecycle_configuration: {
              rules: [
                {
                  id: "MoveToGlacierAfter30Days",
                  status: "Enabled",
                  filter: { prefix: "" },
                  transitions: [
                    {
                      days: 30,
                      storage_class: "GLACIER"
                    }
                  ]
                }
              ]
            }
          )
          puts "✅ Lifecycle policy applied to #{b.name}."
        end
      end
    rescue StandardError => e
      puts "❌ Failed to setup S3 lifecycle: #{e.message}"
    end
  end

  desc "Run all safe cleanup tasks (Snapshots, Elastic IPs, Unattached Volumes, NAT Advice). Usage: rake aws:run_all_cleanup[env_name]"
  task :run_all_cleanup, [:env_name] => :environment do |_t, args|
    env_name = args[:env_name] || "production"

    puts "🚀 Starting Global AWS Cleanup for region: #{ENV['AWS_REGION'] || 'us-east-1'}..."

    # 1. Cleanup Snapshots
    puts "\n--- Task 1: Snapshots ---"
    Rake::Task['aws:cleanup_snapshots'].reenable
    Rake::Task['aws:cleanup_snapshots'].invoke(env_name)

    # 2. Cleanup Elastic IPs
    puts "\n--- Task 2: Elastic IPs ---"
    Rake::Task['aws:cleanup_elastic_ips'].reenable
    Rake::Task['aws:cleanup_elastic_ips'].invoke(env_name)

    # 3. Cleanup Unattached Volumes
    puts "\n--- Task 3: Unattached Volumes ---"
    Rake::Task['aws:cleanup_unattached_volumes'].reenable
    Rake::Task['aws:cleanup_unattached_volumes'].invoke(env_name)

    # 4. List NAT Gateways (Advice only)
    puts "\n--- Task 4: NAT Gateway Advice ---"
    Rake::Task['aws:list_nat_gateways'].reenable
    Rake::Task['aws:list_nat_gateways'].invoke(env_name)

    puts "\n✅ All safe cleanup tasks completed."
    puts "💡 Note: 'Terminate Stopped Instances' and 'S3 Glacier Setup' were skipped as requested."
  end
end
