# app/services/db_restore_service.rb
require 'aws-sdk-ec2'
require 'aws-sdk-iam'
require 'net/ssh'
require 'net/scp'
require 'rake'
require 'json'
require 'shellwords'

class DbRestoreService # rubocop:disable Metrics/ClassLength
  REGION = ENV.fetch("AWS_REGION")
  INSTANCE_NAME = 'DbCheckInstance'.freeze
  LOCAL_SCRIPT_PATH = Rails.root.join("tmp", "db_backup_xtra_#{Rails.env}.sh")
  S3_BUCKET_NAME = if Rails.env.production?
                     "arn:aws:s3:::docs.caphive.com.production-backup-xtra/*"
                   else
                     "arn:aws:s3:::docs.altx.com.staging-backup-xtra/*"
                   end

  REMOTE_SCRIPT_PATH = '/home/ubuntu/db_backup.sh'.freeze
  KEY_PATH = "~/.ssh/#{ENV.fetch('KEYNAME')}.pem".freeze
  SSH_USER = 'ubuntu'.freeze
  VERIFICATION_THRESHOLD_SECONDS = 3600
  AMI_NAME = ENV.fetch("DB_RESTORE_AMI_NAME", "DB-Redis-ES").freeze
  ROLE_NAME = "DbCheckInstanceRole".freeze
  POLICY_NAME = "DbCheckInstancePolicy".freeze
  PROFILE_NAME = "DbCheckInstanceProfile".freeze

  # Entry point for the service. Creates a new instance of the service and runs the restore process.
  def self.run!(instance_name: INSTANCE_NAME)
    new.run!(instance_name: instance_name)
  end

  # Main method to orchestrate the DB restore process.
  # 1. Ensures the backup script is present locally.
  # 2. Finds or launches an EC2 instance for the restore process.
  # 3. Retrieves the instance's IP address and ensures it's reachable.
  # 4. Cleans up remote services on the instance to prepare for the restore.
  # 5. Uploads the backup script to the instance.
  # 6. Executes the backup script remotely.
  # 7. Verifies the timestamp of the restored data to ensure it's recent.
  # 8. Cleans up temporary files and stops the instance.
  def run!(instance_name: INSTANCE_NAME)
    total_start_time = Time.zone.now
    Rails.logger.debug { "[DbRestoreService] Starting DB restore process at #{total_start_time}" }

    # Ensure the backup script is present locally.
    ensure_script_present!

    # Find or launch the EC2 instance for the restore process.
    instance = find_or_launch_instance(instance_name)

    # Retrieve the instance's IP address.
    ip = get_instance_ip(instance)
    raise "Instance has no reachable IP" unless ip

    # Clean up remote services to prepare for the restore.
    cleanup_remote_services(ip)

    # Upload the backup script to the instance.
    upload_script(ip)

    # Execute the backup script remotely.
    script_start_time = Time.zone.now
    run_remote_script(ip)
    script_duration = Time.zone.now - script_start_time

    Rails.logger.debug { "[DbRestoreService] Restore completed for #{ip}" }

    # Verify the timestamp of the restored data.
    verify_timestamp

    # Clean up temporary files and stop the instance.
    cleanup(ip)
    stop_instance(instance)

    # Log the total duration of the process.
    total_duration = Time.zone.now - total_start_time
    Rails.logger.debug { "[DbRestoreService] Script run duration: #{script_duration.round(2)} seconds" }
    Rails.logger.debug { "[DbRestoreService] Total process duration: #{total_duration.round(2)} seconds" }
  end

  private

  # Ensures the backup script is present locally. If not, it generates the script using a Rake task.
  def ensure_script_present!
    if File.exist?(LOCAL_SCRIPT_PATH)
      Rails.logger.debug { "✓ Backup script already exists at #{LOCAL_SCRIPT_PATH}, skipping generation" }
    else
      Rails.logger.debug { "→ Backup script not found at #{LOCAL_SCRIPT_PATH}, generating..." }
      generate_script!
    end
  end

  # Generates the backup script dynamically using a Rake task.
  def generate_script!
    Rails.logger.debug "→ Generating dynamic backup script"
    Rake::Task.clear
    Rails.application.load_tasks
    Rake::Task['xtrabackup:generate_backup_script'].invoke
    raise "Backup script not generated" unless File.exist?(LOCAL_SCRIPT_PATH)
  end

  # Finds an existing EC2 instance by name or launches a new one if none exists.
  def find_or_launch_instance(instance_name)
    instance = find_instance(instance_name)
    if instance
      Rails.logger.debug { "✓ Instance #{instance_name} found: #{instance.instance_id}" }
    else
      Rails.logger.debug { "→ Instance #{instance_name} not found. Launching a new one..." }
      Rails.logger.debug "Ensuring IAM role and policy are set up..."
      ensure_role_and_policy!
      instance = launch_new_instance(instance_name)
    end
    ensure_running(instance)
    instance
  end

  # Launches a new EC2 instance with the specified parameters.
  def launch_new_instance(instance_name) # rubocop:disable Metrics/MethodLength
    Rails.logger.debug { "→ Launching new instance with name #{instance_name}..." }

    ami_id = find_latest_ami_id(AMI_NAME)
    raise "No AMI found with name #{AMI_NAME}" unless ami_id

    key_name = ENV.fetch('KEYNAME')
    key_name = "altx.dev" if key_name == "altxdev"
    subnet_id = ENV.fetch('PRIVATE_SUBNET_ID')

    # Fetch security group IDs from an existing DB instance.
    Rails.logger.debug "→ Fetching security group from existing DB instance..."
    og_db_instance = find_instance(AMI_NAME)
    db_security_group_ids = if og_db_instance
                              og_db_instance.security_groups.pluck(:group_id)
                            else
                              Rails.logger.error "❌ No existing DB instance found to fetch security group"
                              []
                            end

    # Base launch parameters for the EC2 instance.
    launch_params = {
      image_id: ami_id,
      instance_type: og_db_instance&.instance_type || 't3.medium',
      min_count: 1,
      max_count: 1,
      key_name: key_name,
      subnet_id: subnet_id,
      block_device_mappings: [
        {
          device_name: '/dev/xvda',
          ebs: {
            volume_size: ENV.fetch('DB_CHECK_STORAGE').to_i,
            volume_type: 'gp3',
            delete_on_termination: true
          }
        }
      ],
      iam_instance_profile: { name: PROFILE_NAME },
      tag_specifications: [
        {
          resource_type: 'instance',
          tags: [{ key: 'Name', value: instance_name }]
        }
      ]
    }

    # Add security group IDs if available.
    launch_params[:security_group_ids] = db_security_group_ids if db_security_group_ids.present?

    # Launch the EC2 instance.
    launch_response = ec2.run_instances(launch_params)

    new_instance = launch_response.instances.first
    Rails.logger.debug { "✓ Launched new instance: #{new_instance.instance_id}" }
    new_instance
  end

  # Finds the latest AMI ID matching the specified name.
  def find_latest_ami_id(ami_name)
    response = ec2.describe_images(
      filters: [
        { name: 'name', values: ["*#{ami_name}*"] },
        { name: 'state', values: ['available'] }
      ],
      owners: ['self']
    )
    response.images.max_by(&:creation_date)&.image_id
  end

  def refresh_instance(instance_id)
    ec2.describe_instances(instance_ids: [instance_id])
       .reservations
       .flat_map(&:instances)
       .first
  end

  def stop_instance(instance)
    return Rails.logger.debug "→ No instance provided, skipping stop." unless instance

    instance_id = instance.instance_id
    instance = refresh_instance(instance_id)
    return Rails.logger.debug { "✓ Instance #{instance_id} is already stopped." } if instance.state.name == 'stopped'
    return Rails.logger.debug { "→ Instance #{instance_id} is already stopping." } if instance.state.name == 'stopping'

    Rails.logger.debug { "→ Stopping instance #{instance_id}..." }

    ec2.stop_instances(instance_ids: [instance_id])
    Rails.logger.debug { "→ Waiting for instance #{instance_id} to stop..." }

    ec2.wait_until(:instance_stopped, instance_ids: [instance_id])
    Rails.logger.debug { "✓ Instance #{instance_id} stopped" }
  rescue Aws::EC2::Errors::InvalidInstanceIDNotFound => e
    Rails.logger.debug { "✗ Error: Instance ID not found - #{e.message}" }
    ExceptionNotifier.notify_exception(e, data: { instance_id: instance_id })
  rescue Aws::Waiters::Errors::WaiterFailed => e
    Rails.logger.debug { "✗ Timeout: Instance #{instance_id} did not stop in expected time - #{e.message}" }
    ExceptionNotifier.notify_exception(e, data: { instance_id: instance_id })
  rescue StandardError => e
    Rails.logger.debug { "✗ Unexpected error stopping instance #{instance_id}: #{e.message}" }
    ExceptionNotifier.notify_exception(e, data: { instance_id: instance_id })
  end

  def ec2
    @ec2 ||= Aws::EC2::Client.new(
      access_key_id: Rails.application.credentials[:AWS_ACCESS_KEY_ID],
      secret_access_key: Rails.application.credentials[:AWS_SECRET_ACCESS_KEY],
      region: REGION,
      http_open_timeout: 10,
      http_read_timeout: 60
    )
  end

  def find_instance(instance_name)
    ec2.describe_instances(
      filters: [
        { name: 'tag:Name', values: [instance_name] },
        { name: 'instance-state-name', values: %w[pending running stopping stopped] }
      ]
    ).reservations.flat_map(&:instances).first
  end

  def ensure_running(instance)
    if instance.state.name != 'running'
      Rails.logger.debug { "→ Starting instance #{instance.instance_id}..." }
      ec2.start_instances(instance_ids: [instance.instance_id])
    end

    Rails.logger.debug "→ Waiting for instance to pass status checks..."
    ec2.wait_until(:instance_status_ok, instance_ids: [instance.instance_id])
    Rails.logger.debug "✓ Instance is running"
  end

  def get_instance_ip(instance)
    refreshed = ec2.describe_instances(instance_ids: [instance.instance_id])
    inst = refreshed.reservations.first&.instances&.first
    inst&.public_ip_address || inst&.private_ip_address
  end

  # Uploads the backup script to the EC2 instance.
  def upload_script(ip)
    Rails.logger.debug { "→ Uploading script to #{ip}:#{REMOTE_SCRIPT_PATH}" }
    tmp_path = "/home/ubuntu/tmp/db_backup.sh"
    final_path = "/home/ubuntu/db_backup.sh"

    Net::SSH.start(ip, SSH_USER, keys: [KEY_PATH], timeout: 10) do |ssh|
      ssh.exec!("mkdir -p /home/ubuntu/tmp")
    end

    Net::SCP.start(ip, SSH_USER, keys: [KEY_PATH], timeout: 10) do |scp|
      scp.upload!(LOCAL_SCRIPT_PATH.to_s, tmp_path)
    end

    Net::SSH.start(ip, SSH_USER, keys: [KEY_PATH], timeout: 10) do |ssh|
      ssh.exec!("sudo mv #{tmp_path} #{final_path}")
      ssh.exec!("sudo chmod +x #{final_path}")
    end
  end

  # Executes the backup script on the EC2 instance.
  def run_remote_script(ip)
    Rails.logger.debug { "→ Running script on #{ip} (this may take a few minutes...)" }
    sanitized_ip = ip.tr('.', '_')
    timestamp = Time.zone.now.strftime('%Y%m%d_%H%M%S')
    Net::SSH.start(ip, SSH_USER, keys: [KEY_PATH], timeout: 1800) do |ssh|
      File.open("log/db_restore_#{sanitized_ip}_#{timestamp}.log", "wb") do |f|
        ssh.open_channel do |channel|
          channel.exec("sudo bash #{REMOTE_SCRIPT_PATH} restore_primary") do |_ch, success|
            unless success
              msg = "❌ Failed to execute command"
              f.write msg
              Rails.logger.error msg
              ExceptionNotifier.notify_exception(StandardError.new(msg), data: { action: 'execute_restore_primary' })
              next
            end

            channel.on_data do |_ch, data|
              f.write data
              Rails.logger.info("[DbRestoreService] STDOUT: #{data}")
            end

            channel.on_extended_data do |_ch, _type, data|
              f.write data
              Rails.logger.error("[DbRestoreService] STDERR: #{data}")
            end

            channel.on_request("exit-status") do |_ch, data|
              exit_code = data.read_long
              msg = "\n→ Script exited with status #{exit_code}"
              f.write msg
              Rails.logger.info msg
            end
          end
        end

        ssh.loop
      end
    end
  end

  # Verifies the timestamp of the restored data to ensure it's recent.
  def verify_timestamp
    Rails.logger.debug "→ Verifying timestamp from support user"

    timestamp = fetch_timestamp
    return unless validate_timestamp_presence(timestamp)

    ts_time = parse_timestamp(timestamp)
    return unless ts_time

    validate_timestamp_freshness(ts_time)
  end

  # Fetches the timestamp from the database.
  def fetch_timestamp
    ReplicationHealthJob.new.get_timestamp
  end

  # Validates that the timestamp is present.
  def validate_timestamp_presence(timestamp)
    if timestamp.blank?
      Rails.logger.debug "✗ Failed: Empty timestamp"
      ExceptionNotifier.notify_exception(StandardError.new("DB Check FAILED: No timestamp found in last_name"))
      return false
    end
    true
  end

  # Parses the timestamp string into a Time object.
  def parse_timestamp(timestamp)
    Time.zone.parse(timestamp)
  rescue ArgumentError
    Rails.logger.debug { "✗ Failed: Invalid timestamp format '#{timestamp}'" }
    ExceptionNotifier.notify_exception(StandardError.new("DB Check FAILED: Invalid timestamp format: #{timestamp}"))
    nil
  end

  # Validates that the timestamp is within the allowed threshold.
  def validate_timestamp_freshness(ts_time)
    now = Time.zone.now
    diff = now - ts_time

    if diff.between?(0, VERIFICATION_THRESHOLD_SECONDS)
      msg = "✓ Timestamp '#{ts_time}' is recent (Δ #{diff.to_i}s)"
      Rails.logger.debug msg
      EntityMailer.with(subject: "DB Check PASSED", msg: { process: "DB RESTORE CHECK", result: "PASSED", message: msg }).notify_info.deliver_now
      true
    else
      msg = "✗ Timestamp '#{ts_time}' is too old (Δ #{diff.to_i}s)"
      Rails.logger.debug msg
      ExceptionNotifier.notify_exception(StandardError.new("DB Check FAILED: #{msg}"))
      false
    end
  end

  # Cleanup Services on the remote instance to free up memory for the restore process.
  # This includes stopping services like Elasticsearch, Redis, Docker, and clearing cron jobs.
  # It also drops the MySQL database to ensure a clean state for the restore.
  # This method is idempotent and can be called multiple times without adverse effects.
  def cleanup_remote_services(ip)
    Rails.logger.debug { "→ Cleaning up remote services on #{ip}" }

    Net::SSH.start(ip, SSH_USER, keys: [KEY_PATH], timeout: 10) do |ssh|
      kill_elasticsearch_processes(ssh)
      stop_and_disable_service(ssh, "node_exporter.service")
      stop_and_disable_service(ssh, "redis.service")
      stop_and_remove_docker_containers(ssh)
      stop_and_disable_service(ssh, "docker.socket")
      stop_and_disable_service(ssh, "docker")
      clear_cron_jobs(ssh)
      Rails.logger.debug { "  → Dropping MySQL database on #{ip}" }
      drop_mysql_database(ssh)
    end

    Rails.logger.debug { "✓ Remote services cleanup completed on #{ip}" }
  rescue StandardError => e
    Rails.logger.debug { "✗ Remote services cleanup failed: #{e.message}" }
    ExceptionNotifier.notify_exception(e, data: { ip: ip, action: 'cleanup_remote_services' })
  end

  # Stops and disables a specified service on the remote instance.
  def stop_and_disable_service(ssh, service)
    Rails.logger.debug { "  → Stopping and disabling #{service}" }
    ssh.exec!("sudo systemctl stop #{service} 2>/dev/null")
    ssh.exec!("sudo systemctl disable #{service} 2>/dev/null")
  end

  # Stops and removes all Docker containers on the remote instance.
  def stop_and_remove_docker_containers(ssh)
    Rails.logger.debug "  → Stopping and removing all Docker containers"
    container_ids = ssh.exec!("sudo docker ps -aq").to_s.strip
    if container_ids.empty?
      Rails.logger.debug "    → No containers running"
    else
      ssh.exec!("echo '#{container_ids}' | xargs -r sudo docker stop  || true")
      ssh.exec!("echo '#{container_ids}' | xargs -r sudo docker rm -f || true")
    end
    # Prune Docker system: removes unused images, containers, networks, and volumes
    # This will remove all unused images, containers, networks, and volumes
    # It will not remove running containers, so we ensure all are stopped first
    Rails.logger.debug "  → Pruning Docker system"
    ssh.exec!("sudo docker system prune -a --volumes -f || true")
  end

  # Kills all Elasticsearch processes on the remote instance.
  def kill_elasticsearch_processes(ssh)
    Rails.logger.debug "  → Killing Elasticsearch processes"
    pids = ssh.exec!("ps aux | grep '[e]lasticsearch' | awk '{print $2}'").to_s.split("\n")
    if pids.any?
      Rails.logger.debug { "    → Killing PIDs: #{pids.join(', ')}" }
      ssh.exec!("sudo kill #{pids.join(' ')}")
    else
      Rails.logger.debug "    → No Elasticsearch processes found."
    end
  end

  # Clears all user-level and system-level cron jobs on the remote instance.
  # This includes removing user-specific crontabs and system-wide cron directories.
  def clear_cron_jobs(ssh)
    Rails.logger.debug "  → Removing user-level cron jobs"
    ssh.exec!("crontab -r || true")
    ssh.exec!("sudo crontab -r || true")

    Rails.logger.debug "  → Removing system-level cron jobs"
    ssh.exec!("sudo rm -f /etc/cron.d/* /etc/cron.daily/* /etc/cron.hourly/* /etc/cron.weekly/* /etc/cron.monthly/* 2>/dev/null || true")
  end

  # Drops the MySQL database used for the restore process.
  def drop_mysql_database(ssh)
    database_name = "IRM_#{Rails.env}"
    Rails.logger.debug { "  → Dropping MySQL database #{database_name} " }
    ssh.exec!("mysql -u #{Rails.application.credentials['DB_USER']} -p#{Rails.application.credentials['DB_PASS']} -e 'DROP DATABASE IF EXISTS #{database_name};' 2>/dev/null || true")
    Rails.logger.debug "    → Database dropped successfully"
  rescue StandardError => e
    Rails.logger.debug { "✗ Failed to drop database: #{e.message}" }
    ExceptionNotifier.notify_exception(e, data: { action: 'drop_mysql_database', database_name: })
  end

  # Cleans up temporary files on the remote instance after the restore process.
  def cleanup(ip)
    Rails.logger.debug { "→ Cleaning up /tmp/xb* on #{ip}" }
    Net::SSH.start(ip, SSH_USER, keys: [KEY_PATH], timeout: 10) do |ssh|
      ssh.exec!("sudo rm -rf /tmp/xb*")
      Rails.logger.debug "✓ Cleanup successful"
    end
  rescue StandardError => e
    Rails.logger.debug { "✗ Cleanup failed: #{e.message}" }
    ExceptionNotifier.notify_exception(StandardError.new("Cleanup failed on #{ip}: #{e.message}"))
  end

  # Initializes the IAM client for AWS operations.
  # This client is used to manage IAM roles, policies, and instance profiles.
  def iam
    @iam ||= Aws::IAM::Client.new(
      access_key_id: Rails.application.credentials[:AWS_ACCESS_KEY_ID],
      secret_access_key: Rails.application.credentials[:AWS_SECRET_ACCESS_KEY],
      region: REGION,
      http_open_timeout: 10,
      http_read_timeout: 60
    )
  end

  # Ensures the IAM role and policy are set up for the EC2 instance.
  def ensure_role_and_policy!
    policy_arn = find_or_create_policy
    find_or_create_role
    attach_policy(policy_arn)
    find_or_create_profile
  end

  # It checks if the instance profile exists, creates it if not, and attaches the role if it's not already attached.
  # This is necessary for the EC2 instance to assume the role and access AWS resources.
  # @return [nil] if the profile already exists or the role is attached, otherwise
  # returns the result of attaching the role to the instance profile.
  # @raise [Aws::IAM::Errors::NoSuchEntity] if the instance profile does not exist or if the role is not found.
  def find_or_create_profile
    # check if the profile exists
    begin
      iam.get_instance_profile(instance_profile_name: PROFILE_NAME)
      Rails.logger.debug "✓ Instance profile exists"
    rescue Aws::IAM::Errors::NoSuchEntity
      Rails.logger.debug { "→ Creating instance profile #{PROFILE_NAME}" }
      iam.create_instance_profile(instance_profile_name: PROFILE_NAME)
    end

    # check if role is already attached
    begin
      iam.get_instance_profile(instance_profile_name: PROFILE_NAME)
      roles = iam.list_instance_profiles_for_role(role_name: ROLE_NAME).instance_profiles
      if roles.any? { |profile| profile.instance_profile_name == PROFILE_NAME }
        Rails.logger.debug "✓ Role already attached to instance profile"
        nil
      else
        Rails.logger.debug { "→ Attaching role #{ROLE_NAME} to instance profile #{PROFILE_NAME}" }
        # Now attach the role to the instance profile
        iam.add_role_to_instance_profile(
          instance_profile_name: PROFILE_NAME,
          role_name: ROLE_NAME
        )
      end
    rescue Aws::IAM::Errors::NoSuchEntity
      Rails.logger.debug { "→ Instance profile #{PROFILE_NAME} does not exist, creation failed" }
    end
  end

  # Finds or creates an IAM policy with the specified name and policy document.
  def find_or_create_policy
    account_id = iam.get_user.user.arn.split(':')[4]
    policy_arn = "arn:aws:iam::#{account_id}:policy/#{POLICY_NAME}"

    iam.get_policy(policy_arn: policy_arn)
    Rails.logger.debug "✓ Policy exists"
    policy_arn
  rescue Aws::IAM::Errors::NoSuchEntity
    Rails.logger.debug { "→ Creating policy #{POLICY_NAME}" }
    resp = iam.create_policy(
      policy_name: POLICY_NAME,
      policy_document: JSON.pretty_generate(build_policy_document)
    )
    resp.policy.arn
  end

  # Finds or creates an IAM role with the specified name and assume role policy document.
  def find_or_create_role
    iam.get_role(role_name: ROLE_NAME)
    Rails.logger.debug "✓ Role exists"
  rescue Aws::IAM::Errors::NoSuchEntity
    Rails.logger.debug { "→ Creating role #{ROLE_NAME}" }
    iam.create_role(
      role_name: ROLE_NAME,
      assume_role_policy_document: JSON.pretty_generate(build_assume_policy)
    )
  end

  # Attaches the specified policy to the IAM role.
  # It checks if the policy is already attached to avoid duplication.
  def attach_policy(policy_arn)
    attached = iam.list_attached_role_policies(role_name: ROLE_NAME)
                  .attached_policies.any? { |p| p.policy_arn == policy_arn }

    return Rails.logger.debug "✓ Policy already attached" if attached

    Rails.logger.debug "→ Attaching policy"
    iam.attach_role_policy(role_name: ROLE_NAME, policy_arn: policy_arn)
  end

  # Builds the policy document for the IAM role.
  def build_policy_document
    {
      Version: "2012-10-17",
      Statement: [
        {
          Sid: "VisualEditor0",
          Effect: "Allow",
          Action: %w[
            ssm:SendCommand ssm:ListCommands logs:* ec2messages:*
            ssm:ListCommandInvocations ssm:GetCommandInvocation
          ],
          Resource: "*"
        },
        {
          Sid: "VisualEditor1",
          Effect: "Allow",
          Action: "s3:GetObject",
          Resource: S3_BUCKET_NAME
        },
        {
          Effect: "Allow",
          Action: "ses:SendEmail",
          Resource: "*"
        }
      ]
    }
  end

  # Builds the assume role policy document for the IAM role.
  def build_assume_policy
    {
      Version: "2012-10-17",
      Statement: [
        {
          Effect: "Allow",
          Principal: { Service: "ec2.amazonaws.com" },
          Action: "sts:AssumeRole"
        }
      ]
    }
  end
end
