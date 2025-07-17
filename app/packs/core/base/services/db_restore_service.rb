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
  REMOTE_SCRIPT_PATH = '/home/ubuntu/db_backup.sh'.freeze
  KEY_PATH = "~/.ssh/#{ENV.fetch('KEYNAME')}.pem".freeze
  SSH_USER = 'ubuntu'.freeze
  VERIFICATION_THRESHOLD_SECONDS = 3600
  AMI_NAME = ENV.fetch("DB_RESTORE_AMI_NAME", "DB-Redis-ES").freeze

  def self.run!(instance_name: INSTANCE_NAME)
    new.run!(instance_name: instance_name)
  end

  def run!(instance_name: INSTANCE_NAME)
    ensure_script_present!
    instance = find_or_launch_instance(instance_name)

    ip = get_instance_ip(instance)
    raise "Instance has no reachable IP" unless ip

    cleanup_remote_services(ip)
    upload_script(ip)
    run_remote_script(ip)

    Rails.logger.debug { "[DbRestoreService] Restore completed for #{ip}" }

    verify_timestamp # (ip)
    cleanup(ip)
    stop_instance(instance)
  end

  private

  def ensure_script_present!
    if File.exist?(LOCAL_SCRIPT_PATH)
      Rails.logger.debug { "✓ Backup script already exists at #{LOCAL_SCRIPT_PATH}, skipping generation" }
    else
      Rails.logger.debug { "→ Backup script not found at #{LOCAL_SCRIPT_PATH}, generating..." }
      generate_script!
    end
  end

  def generate_script!
    Rails.logger.debug "→ Generating dynamic backup script"
    Rake::Task.clear
    Rails.application.load_tasks
    Rake::Task['xtrabackup:generate_backup_script'].invoke
    raise "Backup script not generated" unless File.exist?(LOCAL_SCRIPT_PATH)
  end

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

  def launch_new_instance(instance_name)
    Rails.logger.debug { "→ Launching new instance with name #{instance_name}..." }

    ami_id = find_latest_ami_id(AMI_NAME)
    raise "No AMI found with name #{AMI_NAME}" unless ami_id

    key_name = ENV.fetch('KEYNAME')
    key_name = "altx.dev" if key_name == "altxdev"
    subnet_id = ENV.fetch('PRIVATE_SUBNET_ID')

    launch_response = ec2.run_instances(
      image_id: ami_id,
      instance_type: 't3.medium',
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
      iam_instance_profile: { name: 'DbCheckInstanceProfile' },
      tag_specifications: [
        {
          resource_type: 'instance',
          tags: [{ key: 'Name', value: instance_name }]
        }
      ]
    )

    new_instance = launch_response.instances.first
    Rails.logger.debug { "✓ Launched new instance: #{new_instance.instance_id}" }
    new_instance
  end

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
    return Rails.logger.debug "✓ Instance is running" if instance.state.name == 'running'

    Rails.logger.debug { "→ Starting instance #{instance.instance_id}..." }
    ec2.start_instances(instance_ids: [instance.instance_id])
    Rails.logger.debug "→ Waiting for instance to pass status checks..."
    ec2.wait_until(:instance_status_ok, instance_ids: [instance.instance_id])
    Rails.logger.debug "✓ Instance is running"
  end

  def get_instance_ip(instance)
    refreshed = ec2.describe_instances(instance_ids: [instance.instance_id])
    inst = refreshed.reservations.first&.instances&.first
    inst&.public_ip_address || inst&.private_ip_address
  end

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

  def run_remote_script(ip)
    Rails.logger.debug { "→ Running script on #{ip} (this may take a few minutes...)" }
    Net::SSH.start(ip, SSH_USER, keys: [KEY_PATH], timeout: 10) do |ssh|
      output = ssh.exec!("sudo bash #{REMOTE_SCRIPT_PATH} restore_primary")
      Rails.logger.info "[DbRestoreService] Output:\n#{output}"
      Rails.logger.debug output
    end
  end

  def verify_timestamp
    Rails.logger.debug "→ Verifying timestamp from support user"

    timestamp = fetch_timestamp
    return unless validate_timestamp_presence(timestamp)

    ts_time = parse_timestamp(timestamp)
    return unless ts_time

    validate_timestamp_freshness(ts_time)
  end

  def fetch_timestamp
    ReplicationHealthJob.new.get_timestamp
  end

  def validate_timestamp_presence(timestamp)
    if timestamp.blank?
      Rails.logger.debug "✗ Failed: Empty timestamp"
      ExceptionNotifier.notify_exception(StandardError.new("DB Check FAILED: No timestamp found in last_name"))
      return false
    end
    true
  end

  def parse_timestamp(timestamp)
    Time.zone.parse(timestamp)
  rescue ArgumentError
    Rails.logger.debug { "✗ Failed: Invalid timestamp format '#{timestamp}'" }
    ExceptionNotifier.notify_exception(StandardError.new("DB Check FAILED: Invalid timestamp format: #{timestamp}"))
    nil
  end

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
    end

    Rails.logger.debug { "✓ Remote services cleanup completed on #{ip}" }
  rescue StandardError => e
    Rails.logger.debug { "✗ Remote services cleanup failed: #{e.message}" }
    ExceptionNotifier.notify_exception(e, data: { ip: ip, action: 'cleanup_remote_services' })
  end

  def stop_and_disable_service(ssh, service)
    Rails.logger.debug { "  → Stopping and disabling #{service}" }
    ssh.exec!("sudo systemctl stop #{service} 2>/dev/null")
    ssh.exec!("sudo systemctl disable #{service} 2>/dev/null")
  end

  def stop_and_remove_docker_containers(ssh)
    Rails.logger.debug "  → Stopping and removing all Docker containers"
    container_ids = ssh.exec!("sudo docker ps -aq").to_s.strip
    if container_ids.empty?
      Rails.logger.debug "    → No containers running"
    else
      ssh.exec!("echo '#{container_ids}' | xargs -r sudo docker stop")
      ssh.exec!("echo '#{container_ids}' | xargs -r sudo docker rm")
    end
  end

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

  def clear_cron_jobs(ssh)
    Rails.logger.debug "  → Removing user-level cron jobs"
    ssh.exec!("crontab -r || true")
    ssh.exec!("sudo crontab -r || true")

    Rails.logger.debug "  → Removing system-level cron jobs"
    ssh.exec!("sudo rm -f /etc/cron.d/* /etc/cron.daily/* /etc/cron.hourly/* /etc/cron.weekly/* /etc/cron.monthly/* 2>/dev/null || true")
  end

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

  def iam
    @iam ||= Aws::IAM::Client.new(
      access_key_id: Rails.application.credentials[:AWS_ACCESS_KEY_ID],
      secret_access_key: Rails.application.credentials[:AWS_SECRET_ACCESS_KEY],
      region: REGION,
      http_open_timeout: 10,
      http_read_timeout: 60
    )
  end

  def ensure_role_and_policy!
    policy_arn = find_or_create_policy
    find_or_create_role
    attach_policy(policy_arn)
  end

  def find_or_create_policy

    
    policy_name = 'DbCheckInstancePolicy'
    account_id = iam.get_user.user.arn.split(':')[4]
    policy_arn = "arn:aws:iam::#{account_id}:policy/#{policy_name}"

    iam.get_policy(policy_arn: policy_arn)
    Rails.logger.debug "✓ Policy exists"
    policy_arn
  rescue Aws::IAM::Errors::NoSuchEntity
    Rails.logger.debug { "→ Creating policy #{policy_name}" }
    resp = iam.create_policy(
      policy_name: policy_name,
      policy_document: JSON.pretty_generate(build_policy_document)
    )
    resp.policy.arn
  end

  def find_or_create_role    
    role_name = 'DbCheckInstanceRole'
    iam.get_role(role_name: role_name)
    Rails.logger.debug "✓ Role exists"
  rescue Aws::IAM::Errors::NoSuchEntity
    Rails.logger.debug { "→ Creating role #{role_name}" }
    iam.create_role(
      role_name: role_name,
      assume_role_policy_document: JSON.pretty_generate(build_assume_policy)
    )
    profile_name = "DbCheckInstanceProfile"
    # create the instance profile
    iam.create_instance_profile(instance_profile_name: profile_name)

    iam.add_role_to_instance_profile(
      instance_profile_name: profile_name,
      role_name: role_name
    )
  end

  def attach_policy(policy_arn)
    role_name = 'DbCheckInstanceRole'
    attached = iam.list_attached_role_policies(role_name: role_name)
                  .attached_policies.any? { |p| p.policy_arn == policy_arn }

    return Rails.logger.debug "✓ Policy already attached" if attached

    Rails.logger.debug "→ Attaching policy"
    iam.attach_role_policy(role_name: role_name, policy_arn: policy_arn)
  end

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
          Resource: "arn:aws:s3:::docs.altx.com.#{Rails.env}-backup-xtra/*"
        },
        {
          Effect: "Allow",
          Action: "ses:SendEmail",
          Resource: "*"
        }
      ]
    }
  end

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
