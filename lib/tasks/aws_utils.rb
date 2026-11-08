# The Dr:: modules these tasks use, loaded explicitly: aws:setup_infra and aws:dr_drill run
# without the Rails environment, so the autoloader cannot find them (see dr_requires.rb)
require_relative 'dr_requires'

module AwsUtils
  require 'mysql2'
  require 'json'
  require 'yaml'
  require 'fileutils'
  require 'open3'
  require 'time' # Time#iso8601 in the DR evidence report
  require 'aws-sdk-ec2'

  def get_branch

    puts "👉 Enter branch name to continue or type 'exit' to abort..."
    input = STDIN.gets.gsub(/\r/, '').strip # Capture input, remove carriage returns, and then strip other whitespace

    if input.downcase == 'exit'
      puts "❌ Task aborted by the user."
      exit 1  # Exit the task with a non-zero status to indicate failure or abortion
    else
      puts "🚀 Continuing with the task..."
      return input # this is the branch to be deployed
      # Place the rest of your task logic here
    end
  end

    def to_label(name)
    "#{name}-#{Time.now.strftime('%Y-%m-%d-%H.%M.%S')}"
    end

    def update_rails_credentials(rails_env, env_variant, key, value)
        raise "Please provide a key and a value. Usage: rake credentials:update[key,value]" unless key && value


        puts "🔑 Updating credentials for Rails.env = #{rails_env}, env_variant = #{env_variant}, key = #{key}, value = #{value}"

        # Decrypt the existing credentials
        encrypted_content = File.read(Rails.root.join('config', 'credentials', "#{rails_env}.#{env_variant}.yml.enc"))
        master_key = File.read(Rails.root.join('config', 'credentials', "#{rails_env}.#{env_variant}.key")).strip
        decryptor = ActiveSupport::MessageEncryptor.new([master_key].pack("H*"), cipher: 'aes-128-gcm')
        credentials = YAML.load(decryptor.decrypt_and_verify(encrypted_content))

        # Update the credentials
        credentials[key] = value

        # Encrypt and save the credentials
        encrypted_data = decryptor.encrypt_and_sign(YAML.dump(credentials))
        File.open(Rails.root.join('config', 'credentials', "#{rails_env}.#{env_variant}.yml.enc"), 'wb') { |file| file.write(encrypted_data) }


        puts "✅ Credentials updated successfully for Rails.env = #{rails_env}, env_variant = #{env_variant}, key = #{key}."

    end

    def update_env_file(file_path, key, new_value)
        # Read all the lines of the file into an array
        lines = File.readlines(file_path)

        # A flag to track whether the key was found and updated
        key_found = false

        # Update the line containing the key, if it exists
        updated_lines = lines.map do |line|
          if line.strip.start_with?("#{key}=")
            key_found = true
            "#{key}=#{new_value}\n"  # Replace the existing line with the new key value
          else
            line  # Keep the existing line as is
          end
        end

        # Append the new key-value pair if the key was not found
        updated_lines << "#{key}=#{new_value}\n" unless key_found

        # Write the updated lines back to the file
        File.open(file_path, 'w') { |file| file.puts(updated_lines) }
    end


    def replace_ip_addresses(file_path, new_ips)

        puts "🔄 Replacing IP addresses #{new_ips} in file: #{file_path}"

        # Replace line by line, SKIPPING comments: the deploy files carry
        # commented-out example `server "IP"` lines, and the old whole-file
        # gsub consumed the replacement IPs on those — leaving the real
        # server line with nil (`server ""`), which cap then tried to SSH
        # as 0.0.0.0:22. Found by the first DR drill.
        ip_index = 0
        updated_lines = File.readlines(file_path).map do |line|
            next line if line.strip.start_with?("#") # commented lines untouched

            line.gsub(/server "(\d+\.\d+\.\d+\.\d+)"/) do
                replacement = new_ips[ip_index]
                # Never write an empty host — fail loudly instead
                raise "Ran out of replacement IPs for #{file_path}: #{new_ips.size} provided, but more active `server` lines exist" if replacement.to_s.empty?

                ip_index += 1
                "server \"#{replacement}\""
            end
        end

        if ip_index < new_ips.size
            # Informational: e.g. staging runs one box but two web IPs exist
            puts "ℹ️ Used #{ip_index}/#{new_ips.size} new IPs (fewer active `server` lines than IPs)."
        end

        File.write(file_path, updated_lines.join)

        puts "✅ IP addresses replaced successfully in file: #{file_path}"
    end


  def run_cmd(command, cwd = nil)
    puts "▸ #{command}"
    opts = cwd ? { chdir: cwd } : {}
    Open3.popen3(command, opts) do |stdin, stdout, stderr, wait_thr|
      stdin.close # nothing to feed it; leaving it open can hang an input-reading child

      # Drain both pipes CONCURRENTLY, and label neither stream as an error.
      #
      # Two problems this replaces:
      #
      # 1. DEADLOCK. Reading stdout to EOF and only *then* reading stderr
      #    hangs the moment the child fills the stderr pipe buffer (~64KB)
      #    while we are still blocked on stdout: the child stops writing,
      #    so stdout never reaches EOF, so we never get to stderr.
      #    Capistrano/SSHKit writes its entire INFO/DEBUG log to stderr, so a
      #    deploy blows past 64KB routinely — this was luck, not design.
      #
      # 2. FALSE ERRORS. Every stderr line was printed as "🚨 Error: ...",
      #    but plenty of tools use stderr for ordinary output: git ("Switched
      #    to a new branch"), SSHKit's whole log, pulumi diagnostics. These
      #    transcripts are kept as DR audit evidence, and a successful run
      #    that reads as a wall of errors misleads whoever reviews it.
      #    Whether the command actually failed is decided by its EXIT STATUS.
      lock = Mutex.new # serialise writes so two streams can't interleave mid-line
      output = [] # also returned, for callers that read a result (e.g. pulumi destroy's count)
      [stdout, stderr].map do |io|
        Thread.new do
          io.each_line do |line|
            lock.synchronize do
              puts line.chomp
              output << line
            end
          end
        end
      end.each(&:join)

      exit_status = wait_thr.value
      unless exit_status.success?
        raise "Command failed with status #{exit_status.exitstatus}: #{command}"
      end

      output.join
    end
  end

  # AMIs kept per Name tag. Single source of truth shared with aws:ebs_cleanup
  # (lib/tasks/aws_ebs.rake): both prune the same AMI groups two hours apart,
  # so if the two keep counts ever disagreed, whichever ran later would
  # silently undo the other's retention policy every week.
  AMI_KEEP_DEFAULT = 3

  # The instance names the weekly cron bakes AMIs for — keep in sync with the
  # aws:create_and_copy_ami entries in config/schedule.rb (DB-Replica and
  # DbCheckInstance have never been part of the weekly bake).
  BAKED_INSTANCE_NAMES = %w[AppServer DB-Redis-ES Observability].freeze

  def cleanup_amis(name_tag, region, number_to_keep=AMI_KEEP_DEFAULT)
    name_tag = name_tag.strip

    puts "🧹 Cleaning up old AMIs with name: #{name_tag} in region: #{region}"
    Aws.config.update({ region: })

    ec2 = Aws::EC2::Client.new

    # flat_map enumerates every page — .images alone reads only the first.
    all_amis = ec2.describe_images({ owners: ['self'] }).flat_map(&:images)
    all_amis.each do |ami|
      tag_value = ami.tags.find { |t| t.key == 'Name' }&.value

      puts "🔍 AMI: #{ami.image_id}, Name Tag: '#{tag_value}'"  # Show exact tag value
    end

    amis = all_amis.select do |ami|
      tag_value = ami.tags.find { |t| t.key == 'Name' }&.value
      tag_value&.strip == name_tag
    end.sort_by { |ami| ami.creation_date }

    # Only completed images take part in the keep window: the cross-region copy
    # this very bake just started is still "pending" here and must neither
    # occupy a survivor slot (evicting the oldest good AMI) nor be deregistered
    # mid-copy. Failed images don't count as survivors either, so a streak of
    # failed copies can't age out the last restorable AMIs.
    available = amis.select { |ami| ami.state == 'available' }
    puts "ℹ️ Found #{amis.length} AMIs with name: #{name_tag} (#{available.length} completed). Retaining #{number_to_keep} AMIs"

    # Retain the last number_to_keep completed AMIs, delete the rest
    if available.length > number_to_keep

      puts "🗑️ Deleting #{available.length - number_to_keep} old AMIs"
      amis_to_delete = available[0...(available.length - number_to_keep)]
    else

      puts "👍 No old AMIs to delete"
      amis_to_delete = []
    end

    amis_to_delete.each do |ami|
      if ami.tags.any? { |t| t.key == 'Retain' && t.value == 'true' }
        puts "⏭ Skipping #{ami.image_id} — tagged Retain=true"
        next
      end

      # Capture the backing snapshot ids BEFORE deregistering — the mappings
      # are gone from describe_images afterwards.
      snapshot_ids = ami.block_device_mappings.filter_map { |m| m.ebs&.snapshot_id }
      begin
        ec2.deregister_image(image_id: ami.image_id)
        puts "✅ Deregistered old AMI: #{ami.image_id} with name: #{ami.name}"
      rescue Aws::EC2::Errors::ServiceError => e
        puts "❌ Failed to deregister AMI: #{ami.image_id}. Error: #{e.message}"
        next # snapshots stay while the AMI still references them
      end

      # Delete the backing snapshots too — deregistering alone strands them,
      # which is how hundreds of orphaned snapshots piled up historically
      # (aws:ebs_cleanup mops up the backlog; this stops minting new ones).
      snapshot_ids.each do |snapshot_id|
        ec2.delete_snapshot(snapshot_id: snapshot_id)
        puts "✅ Deleted backing snapshot: #{snapshot_id}"
      rescue Aws::EC2::Errors::ServiceError => e
        puts "❌ Failed to delete snapshot: #{snapshot_id}. Error: #{e.message}"
      end
    end
  end

  def create_ami_from_snapshot(args)

    puts "📦 Creating AMI from instance: #{args}"
    ami_id = nil
    ec2 = Aws::EC2::Resource.new
    ec2_client = Aws::EC2::Client.new

    instance = ec2.instances(filters: [
      { name: 'tag:Name', values: [args[:instance_name]] },
      { name: 'instance-state-name', values: ['running'] }
    ]).first

    if instance

      puts "✅ Found instance: #{instance.id} for name: #{args[:instance_name]}"
      # Get the volume ID associated with the instance
      volume_id = instance.block_device_mappings[0].ebs.volume_id

      # Create EBS snapshot
      resp = ec2.create_snapshot({
        description: "Snapshot of #{to_label(args[:instance_name])}",
        volume_id: volume_id  # Specify the volume ID of the instance
      })

      snapshot_id = resp.snapshot_id


      puts "📸 Snapshot created: #{snapshot_id}"
      # Wait for snapshot completion
      ec2_client.wait_until(:snapshot_completed, snapshot_ids: [snapshot_id]) do |w|
        w.max_attempts = 30  # Adjust max attempts and delay as needed
        w.delay = 40
      end
      ec2.create_tags({
        resources: [snapshot_id],
        tags: [
          { key: 'Name', value: args[:instance_name] }
        ]
      })

      puts "✅ Snapshot completed: #{snapshot_id} with name: #{args[:instance_name]}"

      ami_name = "#{to_label(args[:instance_name])} - #{Aws.config[:region]}"
      # Create AMI from snapshot
      ami_resp = ec2.register_image({
        name: ami_name,
        architecture: 'x86_64',
        root_device_name: '/dev/sda1', # Add this line
        block_device_mappings: [
          {
            device_name: '/dev/sda1',
            ebs: {
              snapshot_id: snapshot_id,
              volume_type: 'standard'
            }
          }
        ]
      })

      ami_id = ami_resp.image_id

      ec2.create_tags({
        resources: [ami_id],
        tags: [
          { key: 'Name', value: args[:instance_name] }
        ]
      })

      puts "✅ AMI created: #{ami_id} with name: #{args[:instance_name]}"
    else
      raise "No instances found with name #{args[:instance_name]}"
    end

    ami_id
  end

  def copy_ami(ami_id, destination_region)
    # This ec2_client points to the destination region
    dest_ec2_client = Aws::EC2::Client.new(region: destination_region)
    source_ec2_client = Aws::EC2::Client.new()


    # Get the name tag of the source AMI
    source_ami = source_ec2_client.describe_images(image_ids: [ami_id]).images.first
    source_ami_name_tag = source_ami.tags.find { |tag| tag.key == "Name" }&.value


    puts "🏷️ #{source_ami_name_tag}"
    # Start the copy process from the source region
    copy_response = dest_ec2_client.copy_image({
      source_image_id: ami_id,
      source_region: source_ec2_client.config.region,
      name: "Copy-#{ami_id}"
    })

    dest_ec2_client.create_tags({
      resources: [copy_response.image_id],
      tags: [
        { key: 'Name', value: source_ami_name_tag }
      ]
    })


    puts "📤 AMI copy started, New AMI ID: #{copy_response.image_id} in region #{destination_region}"

    # Wait for the AMI to be available
    dest_ec2_client.wait_until(:image_available, image_ids: [copy_response.image_id]) do |w|
      w.max_attempts = 20
      w.delay = 120

      puts "⏳ Waiting for AMI to be available..."
    end


    puts "✅ AMI copy completed: #{copy_response.image_id} in region #{destination_region}"

  end

  def latest_ami(name_tag, region)

    puts "🐞 DEBUG: latest_ami called with name_tag: '#{name_tag}', region: '#{region}'"
    Aws.config.update({ region: })

    ec2 = Aws::EC2::Client.new(region: region) # Explicitly pass region

    latest_ami = ec2.describe_images({
      owners: ['self'],
      filters: [
        { name: "tag:Name", values: [name_tag] }
      ]
    }).images.sort_by { |ami| ami.creation_date }.last

    # `.last` on no matches is nil, and the log line below dereferences it —
    # so an AMI that was never copied to this region surfaced as
    # "undefined method 'image_id' for nil" raised from INSIDE this method,
    # before any caller could check the return value. Return nil cleanly and
    # let callers decide what a missing AMI means.
    if latest_ami.nil?
      puts "⚠️  No AMI tagged '#{name_tag}' owned by this account in #{region}."
      return nil
    end

    puts "✨ Latest AMI found: #{latest_ami.image_id} with name: #{latest_ami.name}, date: #{latest_ami.creation_date}"
    latest_ami
  end

  # latest_ami, but fatal when nothing matches — for callers that cannot
  # meaningfully continue (writing a stack config with a nil AMI id would
  # produce a stack that fails at `pulumi up` instead of here, with a much
  # worse message).
  def latest_ami!(name_tag, region)
    latest_ami(name_tag, region) or
      raise "No AMI tagged '#{name_tag}' owned by this account in #{region}. " \
            "Copy one first: rake \"aws:copy_ami[<source-ami-id>, #{region}, <env_name>]\" " \
            "or bake and copy: rake \"aws:create_and_copy_ami[#{name_tag}, #{region}, <env_name>]\""
  end

  # Reads a single Pulumi config value for a stack. Returns nil when the key is
  # not set (pulumi exits non-zero for missing keys), so callers can distinguish
  # "needs to be set" from "already configured".
  def pulumi_config_get(stack_name, key)
    output, _stderr, status = Open3.capture3("pulumi config get #{key} --stack #{stack_name}", chdir: "../IRM-Infra")
    status.success? ? output.strip : nil
  end

  # Authoritative stack outputs straight from the Pulumi backend. Replaces the
  # old ../IRM-Infra/output.json file handoff: that file is a side-effect write
  # from whichever stack ran `pulumi up` LAST on this machine — reading it for
  # stack A after touching stack B silently hands you the wrong region's IPs.
  # `pulumi stack output --stack <name>` cannot be stale or cross-wired.
  def pulumi_stack_output(stack_name)
    out, err, status = Open3.capture3("pulumi stack output --json --stack #{stack_name}", chdir: "../IRM-Infra")
    raise "pulumi stack output failed for #{stack_name}: #{err}" unless status.success?

    parsed = JSON.parse(out)
    parsed["IPs"] or raise "Stack #{stack_name} has no 'IPs' output — has `pulumi up` been run on it?"
  end

  # Pulumi stack naming convention: <stack>-<region> (e.g. production-ap-south-2).
  # env_variant (in/us) deliberately does NOT appear in the stack name — the region
  # already implies the variant. The variant only selects app-repo file names
  # (.env.<stack>.<variant>, credentials <stack>.<variant>.yml.enc, cap stage
  # <stack>_<variant>). Keep all four conventions in sync when changing this.
  def setup_pulumi_config(stack, web_server_name, db_server_name, region, env_variant)

    puts "🐞 DEBUG: setup_pulumi_config called with stack: '#{stack}', web_server_name: '#{web_server_name}', db_server_name: '#{db_server_name}', region: '#{region}'"
    stack_name = "#{stack}-#{region}"

    # Plain key names — the stack file is already per-region, so no region
    # prefix (the prefixed form caused wrong-region copy-paste bugs; __main__.py
    # keeps a legacy fallback for old files but plain is canonical).
    pulumi_config = {
      "IRM-infra:web_server_ami" => latest_ami!(web_server_name, region).image_id,
      "IRM-infra:db_server_ami" => latest_ami!(db_server_name, region).image_id,
      "IRM-infra:observability_ami" => latest_ami!("Observability", region).image_id
    }

    # Select or create the Pulumi stack. --create makes a brand-new region a
    # one-command setup; ensure_pulumi_stack_config below guarantees a freshly
    # created stack cannot end up half-configured.
    run_cmd("pulumi stack select #{stack_name} --create", "../IRM-Infra")

    pulumi_config.each do |key, value|
      puts "⚙️ Setting pulumi config: #{key} => #{value}"
      run_cmd("pulumi config set --stack #{stack_name} #{key} #{value}", "../IRM-Infra")
    end

    run_cmd("pulumi config set --stack #{stack_name} region #{region}", "../IRM-Infra")

    ensure_pulumi_stack_config(stack_name, region)
  end

  # Guarantees the stack satisfies every config.require() in IRM-Infra/__main__.py
  # (region + 3 AMI keys are set above; domain_name and <region>_key_name are
  # curated values that survive from run to run). For an existing stack these are
  # already in the Pulumi.<stack>.yaml and nothing happens. For a NEW region they
  # must come from ENV — we fail fast here with instructions rather than letting
  # `pulumi up` die later with a bare "Missing required configuration variable".
  def ensure_pulumi_stack_config(stack_name, region)
    if pulumi_config_get(stack_name, "domain_name").to_s.empty?
      domain = ENV["DOMAIN_NAME"]
      raise <<~MSG if domain.to_s.empty?
        Stack #{stack_name} has no domain_name configured and DOMAIN_NAME is not set.
        For a new region/stack, pass the wildcard cert domain for this variant, e.g.:
          DOMAIN_NAME='*.caphive.com' (IN)  or  DOMAIN_NAME='*.caphive.us' (US)
        The value must keep the leading '*.': ACM rejects '*caphive.com', and
        certificate.py/alb.py derive the hosted zone and grafana host from it.
      MSG
      # Single-quote the value: the wildcard '*' must reach pulumi unexpanded
      run_cmd("pulumi config set --stack #{stack_name} domain_name '#{domain}'", "../IRM-Infra")
    end

    # Plain key preferred; accept a legacy region-prefixed value as "configured"
    # so pre-migration stacks don't get prompted needlessly
    if pulumi_config_get(stack_name, "key_name").to_s.empty? &&
       pulumi_config_get(stack_name, "#{region}_key_name").to_s.empty?
      key_name = ENV["AWS_KEY_NAME"]
      raise <<~MSG if key_name.to_s.empty?
        Stack #{stack_name} has no key_name configured and AWS_KEY_NAME is not set.
        EC2 key pairs are per-region and are NOT created by Pulumi: create/import the
        key pair in #{region} first (EC2 -> Key Pairs), then re-run with e.g.:
          AWS_KEY_NAME=caphive
      MSG
      run_cmd("pulumi config set --stack #{stack_name} key_name #{key_name}", "../IRM-Infra")
    end
  end

  # Master DR/new-region orchestration.
  #
  # Two modes, selected by branch_name:
  #   nil/blank  → LEGACY INTERACTIVE: pauses so the operator restores the DB
  #                by hand, commits manually and types a branch name (STDIN).
  #   given      → NON-INTERACTIVE: auto-commits the rewritten config files to
  #                that branch, pushes, and runs the whole recovery unattended —
  #                including primary+replica restore and migration replay.
  # ---------------------------------------------------------------------------
  # DR run transcript
  #
  # The console output of a DR run IS the evidence record that a recovery
  # happened — it gets captured for audit. These helpers give it a structure a
  # reader (or an auditor) can follow without knowing the codebase: a
  # timestamped banner per phase, elapsed time from the start of the run, and a
  # closing summary with per-phase timings that shows where the RTO went.
  # ---------------------------------------------------------------------------
  # Writes to several IOs at once, so a DR run can capture its own console
  # output to a file while still showing it live. Evidence that depends on the
  # operator remembering `| tee` mid-incident is evidence you will not have.
  #
  # Safe for the DR path specifically because nothing there writes straight to
  # fd 1: every external command goes through run_cmd (Open3.popen3, output
  # re-emitted with Ruby `puts`) or Open3.capture3, so swapping $stdout catches
  # all of it. A bare `system()` call would bypass this — there are none in the
  # recovery sequence, and adding one would silently punch a hole in the record.
  class TeeIO
    # Last-resort scrub for credentials that reach the transcript.
    #
    # A DR transcript is written to a file, kept as audit evidence, and handed
    # to auditors — so a secret printed anywhere in the recovery ends up
    # somewhere durable and shared. That already happened once: reset_replication
    # echoed the full CHANGE REPLICATION SOURCE statement, database password
    # included, and the file was one `git add` away from the repository.
    #
    # This is defence in depth, NOT permission to print secrets — pattern
    # matching cannot catch what it has not been taught. The fix for a leak is
    # always to stop emitting it at the source; this only limits the blast
    # radius of the next one.
    # Each pattern must be anchored on an unambiguous credential KEY. A pattern
    # matching a bare flag is not safe here: `/-p(\S+)/` for `mysql -p<pw>` also
    # eats `--parallel`, `pulumi-production` and `ap-south-2-production`, which
    # silently corrupts the very evidence this file exists to preserve. Verified
    # against a real 2MB production transcript: these patterns change exactly
    # the credential line and nothing else.
    #
    # Credential key spellings. The optional `[\w-]*[_-]` prefix is what makes
    # the env-var forms match: an earlier version anchored on `\bpassword`,
    # and `\b` does NOT match between `_` and `P`, so `DB_PASSWORD=…` and
    # `MYSQL_ROOT_PASSWORD: …` — the spellings this codebase actually uses,
    # DB_PASSWORD being the credentials key reset_replication itself reads —
    # passed through untouched.
    #
    # `pwd` requires a prefix (MYSQL_PWD, DB_PWD) rather than allowing a bare
    # match: `pwd` on its own is a shell command that legitimately appears in a
    # transcript, and redacting around it would corrupt the evidence.
    SECRET_KEY = /
      (?:[\w-]*[_-])?(?:password|passwd|secret_access_key|secret_key)
      |
      (?:[\w-]+[_-])pwd
    /xi

    # Contract every pattern must honour, because `scrub` relies on it:
    #   group 1 = key + separator + any OPENING quote  (kept verbatim)
    #   group 2 = the matching CLOSING quote, if any   (kept verbatim)
    #   everything between the two = the secret        (replaced)
    SECRET_PATTERNS = [
      /(SOURCE_PASSWORD\s*=\s*')[^']*(')/i,
      /(IDENTIFIED\s+BY\s+')[^']*(')/i,
      # Generic `key = value` / `key: value`, quoted or bare. The value stops at
      # a quote, comma or semicolon so it can't swallow the rest of a JSON
      # object or a multi-clause SQL statement.
      /(\b#{SECRET_KEY}["']?\s*[=:]\s*["']?)(?!\[REDACTED\])[^\s"',;]+(["']?)/
    ].freeze

    def self.scrub(text)
      SECRET_PATTERNS.reduce(text.to_s) do |acc, pattern|
        acc.gsub(pattern) do
          closing = Regexp.last_match(2)
          # Re-emit the closing quote only if there was one — group 2 is an
          # empty string for the bare `KEY=value` form.
          "#{Regexp.last_match(1)}[REDACTED]#{closing if ["'", '"'].include?(closing)}"
        end
      end
    end

    def initialize(*targets)
      @targets = targets
    end

    def write(*args)
      scrubbed = args.map { |a| self.class.scrub(a) }
      @targets.each do |t|
        t.write(*scrubbed)
        t.flush
      rescue StandardError
        nil # a failing transcript file must never take down a recovery
      end
      args.sum { |a| a.to_s.bytesize }
    end

    def puts(*args)
      return write("\n") if args.empty?

      args.flatten.each do |arg|
        str = arg.to_s
        write(str.end_with?("\n") ? str : "#{str}\n")
      end
      nil
    end

    def print(*args)
      args.each { |a| write(a.to_s) }
      nil
    end

    def printf(fmt, *args)
      write(format(fmt, *args))
    end

    def <<(obj)
      write(obj.to_s)
      self
    end

    def flush
      @targets.each { |t| t.flush rescue nil }
      self
    end

    def sync = true

    # Not endless: Ruby forbids endless definitions for setter methods
    def sync=(value)
      value
    end

    def tty? = false
    def isatty = false
    def fileno = @targets.first.fileno
  end

  # Runs the block with stdout/stderr duplicated into docs/operations/dr/runs/<name>.log.
  # The transcript is the blow-by-blow record behind the evidence report:
  # write_dr_report indexes independently verifiable claims, this is what
  # actually happened, line by line.
  def with_dr_transcript(name)
    path = Rails.root.join("docs", "operations", "dr", "runs", "#{name}.log")
    FileUtils.mkdir_p(File.dirname(path))
    file = File.open(path, "w")
    file.sync = true # survive a hard failure mid-run
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = TeeIO.new(original_stdout, file)
    $stderr = TeeIO.new(original_stderr, file)
    puts "📄 Capturing this run's transcript to #{path.to_s.sub("#{Rails.root}/", '')}"
    yield path
  ensure
    # Restore the real streams FIRST so the closing message reaches the
    # terminal even if the file handle is in a bad state
    $stdout = original_stdout if original_stdout
    $stderr = original_stderr if original_stderr
    file&.close
    puts "📄 Full transcript saved: #{path.to_s.sub("#{Rails.root}/", '')}" if path
  end

  DR_PHASES = [] # [[title, started_at, finished_at], ...]

  # Externally verifiable references collected during the run — see
  # write_dr_report. Keyed by claim; each value is [evidence, how_to_verify].
  DR_EVIDENCE = {}

  # Never let evidence-gathering break a recovery: a DR run failing because it
  # could not look up an instance id would be an absurd trade.
  def record_dr_evidence(claim, evidence, how_to_verify)
    DR_EVIDENCE[claim] = [evidence, how_to_verify]
  rescue StandardError => e
    puts "⚠️  Could not record evidence for '#{claim}': #{e.message}"
  end

  # The Pulumi service keeps its own timestamped, server-side record of every
  # stack update — evidence an operator cannot retroactively edit, unlike
  # anything this script writes about itself.
  def pulumi_update_record(stack_name)
    out, _err, st = Open3.capture3("pulumi stack history --stack #{stack_name} --json --page-size 1",
                                   chdir: "../IRM-Infra")
    return nil unless st.success?

    entry = JSON.parse(out).first or return nil
    { version: entry["version"], result: entry["result"],
      started: entry["startTime"], ended: entry["endTime"] }
  rescue StandardError
    nil
  end

  # Instance ids + launch times straight from the EC2 API. These are the join
  # key an auditor uses against CloudTrail RunInstances events, which is the
  # authoritative third-party record that this infrastructure was really
  # created when the report claims it was.
  def ec2_instance_records(region, private_ips)
    ips = Array(private_ips).reject { |ip| ip.to_s.empty? }
    return [] if ips.empty?

    Aws::EC2::Client.new(region: region)
                    .describe_instances(filters: [{ name: "private-ip-address", values: ips }])
                    .reservations.flat_map(&:instances)
                    .map { |i| "#{i.instance_id} (#{i.private_ip_address}, launched #{i.launch_time.utc.iso8601})" }
  rescue StandardError
    []
  end

  def dr_run_started_at
    @dr_run_started_at ||= Time.now
  end

  def hms(seconds)
    format('%d:%02d', seconds / 60, seconds % 60)
  end

  # Closes the open phase (if any) so its duration is recorded.
  def finish_dr_phase
    open_phase = DR_PHASES.last
    open_phase[2] = Time.now if open_phase && open_phase[2].nil?
  end

  def dr_phase(title)
    finish_dr_phase
    started = Time.now
    DR_PHASES << [title, started, nil]
    puts ""
    puts "═" * 78
    puts "▶ #{title}"
    puts "  #{started.strftime('%Y-%m-%d %H:%M:%S %Z')}   ·   T+#{hms((started - dr_run_started_at).round)} elapsed"
    puts "═" * 78
  end

  # Closing block: the part that actually gets screenshotted / pasted into a
  # compliance record, so it repeats the identifying facts rather than assuming
  # the reader still has the top of the transcript.
  def dr_summary(stack:, region:, env_variant:, branch:, result:, extra: {})
    finish_dr_phase
    finished = Time.now
    puts ""
    puts "═" * 78
    puts "  DISASTER RECOVERY RUN — #{result}"
    puts "═" * 78
    {
      "Stack" => "#{stack} (#{env_variant})",
      "Region" => region,
      "Branch deployed" => branch,
      "Started" => dr_run_started_at.strftime('%Y-%m-%d %H:%M:%S %Z'),
      "Finished" => finished.strftime('%Y-%m-%d %H:%M:%S %Z'),
      # Deliberately NOT labelled "RTO": this excludes detection, disaster
      # declaration and DNS cutover/TTL. See write_dr_report for the full scope.
      "Rebuild time" => "#{hms((finished - dr_run_started_at).round)} (excludes detection, declaration, DNS cutover)"
    }.merge(extra).each { |k, v| puts "  #{k.ljust(21)}: #{v}" }

    unless DR_PHASES.empty?
      puts ""
      puts "  Phase timings:"
      DR_PHASES.each do |title, started, ended|
        puts "    #{hms(((ended || finished) - started).round).rjust(6)}  #{title}"
      end
    end
    puts "═" * 78
    puts ""
  end

  # Writes the per-run evidence file. Deliberately NOT a self-contained
  # narrative: a markdown file a script writes about itself is a claim, not
  # proof, and the first thing an auditor asks is what stopped someone editing
  # it. Every row therefore names a record held OUTSIDE this repo (Pulumi's
  # service-side update history, CloudTrail, GitHub, S3) and the command that
  # checks it, so the report is an index of things the auditor can confirm
  # independently rather than something they have to take on trust.
  # Pulls the per-host dr:verify scorecard out of the captured transcript.
  #
  # Those checks run REMOTELY (cap recovery:verify -> rake dr:verify on each app
  # server) and only ever exist as console output, so the transcript is the only
  # place they can be recovered from. That is exactly why the report is
  # generated from the transcript rather than assembled independently: an
  # auditor gets the individual checks, not a summary asserting they passed.
  def parse_verify_scorecard(transcript_path)
    return {} unless transcript_path && File.exist?(transcript_path)

    scorecard = {}
    host = nil
    File.foreach(transcript_path) do |raw|
      line = raw.gsub(/\e\[[0-9;]*m/, "")                    # ANSI colour
                .sub(/\A\s*\d+\s/, "")                       # capistrano's "  01 " prefix
                .sub(/\A\s*(DEBUG|INFO)\s+\[\w+\]\s*/, "")
                .strip
      if (m = line.match(/dr:verify on (\S+)/))
        host = m[1]
        scorecard[host] ||= []
      elsif line.match?(/dr:verify — \d+ checks/)
        host = nil # this host's scorecard is finished
      elsif host && (m = line.match(/\A(✅|❌|⚠️)\s+(.+)\z/))
        scorecard[host] << [m[1], m[2].strip]
      end
    end
    scorecard
  end

  # The point the database was recovered to: the backup chain the primary restore used, as the
  # baked script prints it ("Found latest full backup: 2026-11-07_230001-full", then
  # "INCREMENTAL     2026-11-08_070001-incr"). The newest key's timestamp is the recovery point.
  # nil when the run never reached the restore.
  def parse_recovery_point(transcript_path)
    return nil unless transcript_path && File.exist?(transcript_path)

    full = incr = nil
    File.foreach(transcript_path) do |raw|
      line = raw.gsub(/\e\[[0-9;]*m/, "")
      next unless line.include?("[primary]")

      full ||= line[/Found latest full backup: (\S+-full)/, 1]
      incr ||= line[/INCREMENTAL\s+(\S+-incr)/, 1]
      break if full && incr
    end
    key = incr || full
    return nil unless key

    # "2026-11-08_070001-incr" → 2026-11-08 07:00:01 UTC (the scripts name backups in UTC)
    parts = key.match(/\A(\d{4})-(\d{2})-(\d{2})_(\d{2})(\d{2})(\d{2})/)&.captures
    { full: full, incr: incr, at: parts && Time.utc(*parts.map(&:to_i)) }
  end

  # Writes the per-run evidence report, HTML and Markdown (openspec dr-drill-report-redesign).
  #
  # Every factual claim is either tied to a record held OUTSIDE this repo with
  # the command that checks it (DR_EVIDENCE), or reproduced from the run's own
  # transcript (the verify scorecard). What the report adds is legibility: the
  # answer first, every problem with what to do, every step and check explained
  # (Dr::ReportCatalog). Both files come from ONE model (Dr::ReportModel), so
  # they cannot disagree. Never raises: a report must never fail a recovery.
  def write_dr_report(stack:, region:, env_variant:, branch:, result:, started_at:, drill: false)
    finished = Time.now
    dir = Rails.root.join("docs", "operations", "dr", "runs")
    FileUtils.mkdir_p(dir)

    # The verify scorecard comes from the run's own transcript
    scorecard = parse_verify_scorecard(dir.join("#{branch}.log"))
    model = Dr::ReportModel.build(
      phases: DR_PHASES, scorecard: scorecard, evidence: DR_EVIDENCE, result: result,
      recovery_point: parse_recovery_point(dir.join("#{branch}.log")),
      stack: stack, region: region, env_variant: env_variant, branch: branch,
      started_at: started_at, finished: finished, drill: drill,
      # "deleted afterwards" is only said when this drill really tears down
      teardown: ENV["TEARDOWN"] == "true",
      executed_by: "#{ENV['USER'] || 'unknown'}@#{`hostname`.strip}"
    )

    # Markdown: reads in GitHub next to the drill log
    path = dir.join("#{branch}.md")
    File.write(path, Dr::ReportRender.markdown(model))
    puts "🧾 Evidence report written to #{path.to_s.sub("#{Rails.root}/", '')}"

    # HTML: the reader-facing copy - light, self-contained, opens offline
    html_path = dir.join("#{branch}.html")
    File.write(html_path, Dr::ReportRender.html(model))
    puts "📄 Auditor report (HTML) written to #{html_path.to_s.sub("#{Rails.root}/", '')}"

    path
  rescue StandardError => e
    puts "⚠️  Could not write DR report: #{e.class}: #{e.message}"
    nil
  end

  # Every local key that might open a DR server: the DB key (KEYNAME) and the
  # app servers' deploy key from config/deploy/<stack>_<variant>.rb.
  def dr_ssh_keys(stack, env_variant)
    deploy_file = Rails.root.join("config", "deploy", "#{stack}_#{env_variant}.rb")
    deploy_keys = File.exist?(deploy_file) ? File.read(deploy_file).scan(/keys:\s*\[\s*'([^']+)'/).flatten : []
    (["~/.ssh/#{ENV.fetch('KEYNAME', '')}.pem"] + deploy_keys).map { |k| File.expand_path(k) }.uniq.select { |k| File.file?(k) }
  end

  # How long setup_infra waits for freshly created app servers to accept SSH.
  SSH_READY_DEADLINE_SECONDS = 300

  # Waits until every new app server accepts SSH, so the first deploy step does
  # not race the boot (2026-09-12 18:32: Net::SSH::ConnectionTimeout two seconds
  # after pulumi up). Raises, naming the server, if one never answers.
  def wait_for_ssh(stack, env_variant, app_ips)
    require "net/ssh"
    keys = dr_ssh_keys(stack, env_variant)
    app_ips.each do |ip|
      # Monotonic: a wall-clock jump must not stretch or cut the deadline
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + SSH_READY_DEADLINE_SECONDS
      begin
        Net::SSH.start(ip, "ubuntu", keys: keys, keys_only: true, non_interactive: true, timeout: 10,
                                     verify_host_key: :never) { |ssh| ssh.exec!("true") }
        puts "🔌 #{ip} accepts SSH"
      rescue StandardError => e
        raise "App server #{ip} did not accept SSH within #{SSH_READY_DEADLINE_SECONDS / 60} min (#{e.class}: #{e.message})" \
          if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep 10
        retry
      end
    end
  end

  # Opens SSH to a DB server from the operator's machine, hopping through an app
  # server (DB servers accept SSH only from there). The app server forwards the
  # TCP stream (-W); the same keys are offered on both hops. Host keys change on
  # every rebuild, so they are not pinned (matches run_baked_restore).
  def dr_db_ssh(app_ip, db_host, keys, &)
    require "net/ssh"
    require "net/ssh/proxy/command"
    require "shellwords"
    key_opts = keys.map { |k| "-i #{Shellwords.escape(k)}" }.join(" ")
    proxy_cmd = "ssh #{key_opts} -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null " \
                "-o ConnectTimeout=10 -W %h:%p ubuntu@#{app_ip}"
    Net::SSH.start(db_host, "ubuntu", keys: keys, keys_only: true, non_interactive: true, timeout: 15,
                                      verify_host_key: :never, proxy: Net::SSH::Proxy::Command.new(proxy_cmd), &)
  end

  # How long the early strip keeps retrying while freshly created boxes boot.
  EARLY_STRIP_DEADLINE_SECONDS = 120

  # Strips the old, marker-blind backup job (Dr::OldBackupJobs) from freshly
  # created DR DB boxes as early as possible. The boxes are clones of the live
  # DB box, so its hourly /home/ubuntu/backup_db.sh comes along and would write
  # into the live backup chain from both the primary and the replica until the
  # restore strips it. Doing it here, right after pulumi up, shrinks that window
  # from ~9 minutes to ~2-3.
  #
  # Best effort by design — it runs before anything is deployed, from the
  # operator's machine, hopping through an app server (DB boxes accept SSH only
  # from there). Any failure is a warning; run_baked_restore strips again.
  def strip_old_backup_jobs_early(stack, env_variant, app_ip, db_hosts)
    require "net/ssh"
    require "net/ssh/proxy/command"
    require "shellwords"
    puts "🧹 Stripping old backup jobs from the new DB boxes (best effort; the restore does it again)"

    keys = dr_ssh_keys(stack, env_variant)
    if app_ip.to_s.empty? || keys.empty?
      puts "⚠️  Early strip skipped — no app server address or no local SSH key; the restore will strip instead"
      return
    end

    db_hosts.compact.uniq.each do |db_host|
      # Monotonic: a wall-clock jump (NTP) must not stretch or cut the deadline
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + EARLY_STRIP_DEADLINE_SECONDS
      begin
        dr_db_ssh(app_ip, db_host, keys) { |ssh| Dr::OldBackupJobs.strip!(ssh, prefix: "  [#{db_host}] ") }
      rescue StandardError => e
        # Boxes created seconds ago may not accept SSH yet — retry until the deadline
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
          sleep 15
          retry
        end
        puts "⚠️  Early strip on #{db_host} gave up (#{e.class}: #{e.message}) — the restore will strip instead"
      end
    end
  rescue StandardError => e
    puts "⚠️  Early strip skipped (#{e.class}: #{e.message}) — the restore will strip instead"
  end

  def setup_infra(stack, web_server_name, db_server_name, region, env_variant, branch_name = nil)
    # Reset the transcript so a re-run in the same process starts clean
    DR_PHASES.clear
    DR_EVIDENCE.clear
    @dr_run_started_at = Time.now

    puts ""
    puts "█" * 78
    puts "  DISASTER RECOVERY SEQUENCE"
    puts "  #{stack} (#{env_variant}) → #{region}"
    puts "  Operator: #{ENV['USER'] || 'unknown'}@#{`hostname`.strip}   ·   #{@dr_run_started_at.strftime('%Y-%m-%d %H:%M:%S %Z')}"
    puts "█" * 78

    dr_phase "Phase 1/9 · Refresh Pulumi stack configuration"
    setup_pulumi_config(stack, web_server_name, db_server_name, region, env_variant)

    dr_phase "Phase 2/9 · Provision infrastructure (pulumi up)"
    puts "⬆️ Running pulumi up for stack: #{stack}. (This could take a long time, please be patient)"
    # Run pulumi to setup the aws infra
    run_cmd("pulumi up --stack #{stack}-#{region} --yes --color=always", "../IRM-Infra")

    if (upd = pulumi_update_record("#{stack}-#{region}"))
      record_dr_evidence("Infrastructure provisioned in #{region}",
                         "Pulumi update ##{upd[:version]} — #{upd[:result]}, #{upd[:started]} → #{upd[:ended]}",
                         "`pulumi stack history --stack #{stack}-#{region}` (server-side record, Pulumi console)")
    end
    # Get the pulumi output

    dr_phase "Phase 3/9 · Rewrite config with the new host addresses"
    puts "📥 Getting pulumi output (authoritative, from the stack backend)"
    pulumi_output = pulumi_stack_output("#{stack}-#{region}")

    pulumi_output.each do |key, value|
      puts "✅ Got pulumi output: #{key} => #{value}"
    end

    # NOTE: output.json has NO "IPs" wrapper — its top-level keys are
    # private_ips/public_ips/... (see outputs.py). The old dig("IPs", ...)
    # calls silently returned nil, which would have written nil into the
    # credentials and deploy files mid-DR. Guard against nil explicitly.
    ["DB_HOST", "DB_HOST_REPLICA"].each do |key|
      rails_env = stack
      value = pulumi_output.dig("private_ips", key)
      raise "Pulumi output missing private_ips.#{key} — check ../IRM-Infra/output.json" if value.to_s.empty?

      update_rails_credentials(rails_env, env_variant, key, value) # Pass env_variant here
    end

    elastic_url = pulumi_output.dig("private_ips", "DB_HOST")
    update_env_file(".env.#{stack}.#{env_variant}", "ELASTIC_SEARCH_URL", "#{elastic_url}:9200") # Use env_variant in file path
    redis_url = pulumi_output.dig("private_ips", "DB_HOST")
    update_env_file(".env.#{stack}.#{env_variant}", "REDIS_URL", "redis://#{redis_url}:6379") # Use env_variant in file path

    # Update the deploy files with the new IP addresses.
    # AppServers is exported via Output.all([...]) and lands double-nested in
    # output.json ([["ip1","ip2"]]); dig(...,0) unwraps to the inner ARRAY,
    # which is what replace_ip_addresses expects (one IP per `server` line).
    app_server_ips = pulumi_output.dig("public_ips", "AppServers", 0)
    raise "Pulumi output missing public_ips.AppServers — check ../IRM-Infra/output.json" unless app_server_ips.is_a?(Array) && app_server_ips.any?

    replace_ip_addresses(Rails.root.join('config', 'deploy', "#{stack}_#{env_variant}.rb"), app_server_ips)
    # aws:dr_drill's pre-teardown stop checks the deploy file against these
    @dr_app_server_ips = app_server_ips

    # A drill marks its own stack: tagged error mail, no WhatsApp pages
    # (lib/drill_stack.rb). Committed only on the drill branch, with the other
    # config above; a real recovery never sets it.
    update_env_file(".env.#{stack}.#{env_variant}", "DR_DRILL_STACK", region) if Dr::BackupSchedule.drill?

    # Instance ids are the join key against CloudTrail — the authoritative
    # third-party record that these machines were created when we say they were.
    db_hosts = [pulumi_output.dig("private_ips", "DB_HOST"), pulumi_output.dig("private_ips", "DB_HOST_REPLICA")]
    instances = ec2_instance_records(region, db_hosts)
    unless instances.empty?
      record_dr_evidence("Database instances launched in #{region}",
                         instances.join("; "),
                         "CloudTrail `RunInstances` events in #{region}; `aws ec2 describe-instances --region #{region}`")
    end
    record_dr_evidence("Recovered stack endpoints",
                       "app servers #{app_server_ips.join(', ')}; DB primary #{db_hosts[0]}, replica #{db_hosts[1]}",
                       "`pulumi stack output --stack #{stack}-#{region}`")

    # The new DB boxes are clones of the live box and carry its old,
    # marker-blind backup job — strip it now rather than ~8 minutes from now
    # at the restore. Best effort: never fails the DR (the restore strips again).
    wait_for_ssh(stack, env_variant, app_server_ips)
    strip_old_backup_jobs_early(stack, env_variant, app_server_ips.first, db_hosts)

    if branch_name.to_s.strip.empty?
      # ------------------- LEGACY INTERACTIVE MODE -------------------
      puts "\n#######################"
      puts "Manually load the backup DB into the primary DB. On the DB box run:"
      puts "  sudo /usr/local/bin/db_backup_xtra.sh restore_primary   (baked AMI)"
      puts "or push the generated tmp/db_backup_xtra_#{stack}.sh and run 'restore_primary'."
      puts "#########################"

      puts "\n#######################"
      puts "⚠️ You need to commit your code, with the updated credentials, .env and deploy files, before deploying the app."
      puts "👉 Please enter branch name to deploy to continue once you have committed the code."
      puts "#########################"
      branch_name = get_branch
      restore_tasks = ["recovery:restore_replica_db"] # primary was restored by hand above
    else
      # ------------------- NON-INTERACTIVE MODE -------------------
      dr_phase "Phase 4/9 · Commit and push the DR branch (#{branch_name})"
      commit_dr_changes(stack, env_variant, region, branch_name)
      # The pushed SHA proves WHICH code was recovered onto — and GitHub's own
      # push timestamp corroborates when, independently of this machine's clock.
      record_dr_evidence("Application code deployed",
                         "commit `#{`git rev-parse HEAD`.strip}` on branch `#{branch_name}` (pushed to origin)",
                         "`git log -1 #{`git rev-parse --short HEAD`.strip}`; GitHub branch push timestamp")
      # Primary + replica restore both run remotely from the app server
      # (recovery:load_db_from_backups), then migrations newer than the backup
      # are replayed BEFORE traffic is switched back.
      restore_tasks = ["recovery:load_db_from_backups", "recovery:migrate"]
    end

    dr_phase "Phase 5/9 · Deploy the application to both app servers"
    # Deploy the app
    run_cmd("branch=#{branch_name} LB=true bundle exec cap #{stack}_#{env_variant} recovery:delete_old_assets")
    # SKIP_MIGRATE: deploy-time migrations are meaningless before the restore
    # (and fatal on fresh Packer AMIs, whose virgin MySQL has no IRM_<env> yet).
    # recovery:migrate replays real migrations AFTER the restore instead.
    run_cmd("branch=#{branch_name} LB=true SKIP_NOTIFICATION=true SKIP_MIGRATE=true bundle exec cap #{stack}_#{env_variant} IRM:setup")
    # The AMI bakes its Ruby via `rvm install` at Packer build time
    # (appserver.ami.pkr.hcl); a box rebuilt from an AMI older than the repo's
    # .ruby-version would otherwise run capistrano-bundler's install below
    # under the WRONG Ruby. IRM:install_ruby (config/deploy.rb) is idempotent —
    # a no-op once the target is already the RVM default — so this is safe on
    # every DR run, not just the ones that actually need it.
    run_cmd("branch=#{branch_name} LB=true SKIP_NOTIFICATION=true bundle exec cap #{stack}_#{env_variant} IRM:install_ruby")
    run_cmd("branch=#{branch_name} LB=true SKIP_NOTIFICATION=true SKIP_MIGRATE=true bundle exec cap #{stack}_#{env_variant} deploy")
    # Fresh boxes booted BEFORE whenever installed the @reboot crontab, so
    # start the services those entries would have started (xirr_py,
    # prometheus_exporter) — idempotent no-op on already-running boxes
    run_cmd("branch=#{branch_name} LB=true bundle exec cap #{stack}_#{env_variant} IRM:start_boot_services")

    dr_phase "Phase 6/9 · Take traffic offline (nginx maintenance mode)"
    # Now stop sidekiq, puma and monitoring and switch to maintenance mode
    run_cmd("branch=#{branch_name} LB=true bundle exec cap #{stack}_#{env_variant} nginx:switch_maintenance")

    dr_phase "Phase 7/9 · Restore the database from S3 backups"
    # Load the DB from backups (and replay migrations in non-interactive mode)
    restore_tasks.each do |task|
      run_cmd("branch=#{branch_name} bundle exec cap #{stack}_#{env_variant} #{task}")
    end
    backup_bucket = "#{ENV.fetch('AWS_S3_BUCKET', nil)}-backup-xtra"
    record_dr_evidence("Data restored from real backups",
                       "source bucket `#{backup_bucket}` (full + incremental chain; keys named in the transcript)",
                       "`aws s3 ls s3://#{backup_bucket}/` — compare object timestamps against the run window")

    dr_phase "Phase 8/9 · Start the search rebuild (background)"
    # Elasticsearch is not backed up: the new DB box's indexes are empty, so
    # every search box would return nothing. Queue the rebuild now (Redis is up;
    # the job waits for Sidekiq, which starts with traffic in the next phase):
    # users get the site at once and search fills in ("enqueue and move on",
    # 2026-11-08). dr:verify and the report show its progress.
    run_cmd("branch=#{branch_name} LB=true bundle exec cap #{stack}_#{env_variant} recovery:reindex_search_later")

    dr_phase "Phase 9/9 · Restore traffic and verify the recovered stack"
    # Switch back to the app and remove maintenance mode
    run_cmd("branch=#{branch_name} LB=true bundle exec cap #{stack}_#{env_variant} nginx:switch_app")

    # FINAL GATE: prove the recovered stack actually SERVES — nginx/puma/
    # sidekiq on every app server, MySQL/Redis/ES/S3 reachable with the app's
    # real credentials, DB-box daemons up, backup cron armed on the primary,
    # replication flowing. run_cmd raises on failure, so a DR run (and
    # therefore a drill) can no longer report success while the site is dead.
    run_cmd("branch=#{branch_name} LB=true bundle exec cap #{stack}_#{env_variant} recovery:verify")
    # run_cmd raises on a non-zero exit and dr:verify aborts non-zero on any
    # failed check, so reaching this line IS the proof the stack served.
    # ...and through the load balancer users will hit: certificate, target health, a request to
    # the database and the sign-in page over HTTPS. Raises like a failed verify.
    edge_fails = dr_edge_checks(stack, region)
    raise "Checks through the load balancer failed (#{edge_fails}) — see the load-balancer scorecard above" if edge_fails.positive?

    record_dr_evidence("Recovered stack verified serving",
                       "`recovery:verify` passed on every app server at #{Time.now.utc.iso8601} (per-check scorecard in the transcript)",
                       "re-run `LB=true bundle exec cap #{stack}_#{env_variant} recovery:verify`")

    dr_summary(stack: stack, region: region, env_variant: env_variant,
               branch: branch_name, result: "COMPLETE — STACK VERIFIED SERVING",
               extra: {
                 "App servers" => app_server_ips.join(", "),
                 "DB primary" => pulumi_output.dig("private_ips", "DB_HOST").to_s,
                 "DB replica" => pulumi_output.dig("private_ips", "DB_HOST_REPLICA").to_s,
                 "Verification" => "recovery:verify — all checks passed"
               })

    # Only written here for a REAL recovery; aws:dr_drill writes its own (with
    # drill: true) from its ensure block so failed drills get a report too.
    unless @dr_report_deferred
      write_dr_report(stack: stack, region: region, env_variant: env_variant,
                      branch: branch_name, result: "COMPLETE — STACK VERIFIED SERVING",
                      started_at: dr_run_started_at)
    end

    puts "👉 Edge check before going live: rake \"aws:dr_verify_edge[#{stack}, #{region}]\" then aws:dns_cutover"
  end

  # Commits ONLY the files setup_infra just rewrote to a dedicated DR branch and
  # pushes it (Capistrano deploys by cloning the remote, so the branch must
  # exist on origin). Never `git add -A` — stray local changes on the operator
  # machine must not ride along in a DR commit.
  def commit_dr_changes(stack, env_variant, region, branch_name)
    files = [
      "config/credentials/#{stack}.#{env_variant}.yml.enc",
      ".env.#{stack}.#{env_variant}",
      "config/deploy/#{stack}_#{env_variant}.rb"
    ]

    puts "📝 Committing DR config changes to branch '#{branch_name}'"
    # -B: create the branch, or reset an existing one to the current HEAD —
    # makes re-runs of the same DR command converge instead of failing
    run_cmd("git checkout -B #{branch_name}")

    changes = `git status --porcelain -- #{files.join(' ')}`.strip
    if changes.empty?
      puts "ℹ️ No changes in #{files.join(', ')} — nothing to commit (re-run?)."
    else
      run_cmd("git add #{files.join(' ')}")
      run_cmd(%(git commit -m "DR infra update: #{stack}-#{region} (#{env_variant}) #{Time.now.strftime('%Y-%m-%d %H:%M')}"))
    end
    # Push either way so the branch exists on origin for the cap deploy
    run_cmd("git push -u origin #{branch_name}")
  end



  def reset_replication(server_id)
    source_host = Rails.application.credentials[:DB_HOST]
    source_user = Rails.application.credentials[:DB_USER]
    source_password = Rails.application.credentials[:DB_PASS]
    source_database = "IRM_#{Rails.env}"
    source_port = 3306

    destination_host = Rails.application.credentials[:DB_HOST_REPLICA]
    destination_user = Rails.application.credentials[:DB_USER]
    destination_password = Rails.application.credentials[:DB_PASS]
    destination_port = 3306

    source_client = Mysql2::Client.new(
      host: source_host,
      username: source_user,
      password: source_password,
      database: source_database,
      port: source_port
    )

    destination_client = Mysql2::Client.new(
      host: destination_host,
      username: destination_user,
      password: destination_password,
      port: destination_port
    )

    # MySQL 8.4 renamed SHOW MASTER STATUS -> SHOW BINARY LOG STATUS, and the
    # old spelling was REMOVED rather than kept as an alias. The fleet runs both
    # versions today — staging is on 8.4.7, production on 8.0.46 — so neither
    # statement works everywhere and hardcoding the 8.4 form made this raise
    # "syntax error ... near 'LOG STATUS'" on the first production DR that got
    # this far, after the restore itself had already succeeded.
    #
    # Chosen by server version rather than by rescuing the syntax error: MySQL
    # error text is localisable, so matching on it would be a latent trap.
    #
    # NOTE: this is a symptom of staging and production running different MySQL
    # majors — a staging drill cannot validate production's replication path.
    major, minor = source_client.server_info[:version].to_s.split('.').map(&:to_i)
    binlog_status_sql = if major > 8 || (major == 8 && minor >= 4)
                          'SHOW BINARY LOG STATUS'
                        else
                          'SHOW MASTER STATUS'
                        end
    puts "Source MySQL #{source_client.server_info[:version]} — using `#{binlog_status_sql}`"
    result = source_client.query(binlog_status_sql)
    row = result.first
    raise "Binary logging not enabled on source" unless row
    binlog_file = row['File']
    binlog_position = row['Position']
    puts "Current binary log file: #{binlog_file}, position: #{binlog_position}"

    # 8.4: CHANGE MASTER TO -> CHANGE REPLICATION SOURCE TO
    change_source_query = <<~SQL
      CHANGE REPLICATION SOURCE TO
        SOURCE_HOST='#{source_host}',
        SOURCE_USER='#{source_user}',
        SOURCE_PASSWORD='#{source_password}',
        SOURCE_PORT=#{source_port},
        SOURCE_LOG_FILE='#{binlog_file}',
        SOURCE_LOG_POS=#{binlog_position}
    SQL

    # set a distinct server_id on the replica (runtime)
    puts "Setting server_id to #{server_id}"
    destination_client.query("SET GLOBAL server_id = #{server_id}")

    # reset and configure replica
    destination_client.query('STOP REPLICA')
    destination_client.query('RESET REPLICA ALL')
    # REDACT the password before echoing the statement. This line printed the
    # database credential in plaintext on every DR run — to the operator's
    # console, into log/capistrano.log, and (once runs began capturing their own
    # transcript for audit) into a file that was one `git add` away from being
    # committed to the repository. Echo the shape of the statement, never the
    # secret in it.
    puts "Setting up replication on the destination with query: " \
         "#{change_source_query.squish.sub(/SOURCE_PASSWORD='[^']*'/, "SOURCE_PASSWORD='[REDACTED]'")}"
    destination_client.query(change_source_query)

    puts 'Starting replica'
    destination_client.query('START REPLICA')

    status = destination_client.query('SHOW REPLICA STATUS')
    puts status.first.inspect
  end


  # ---------------------------------------------------------------------------
  # S3 bucket + cross-region replication helpers
  # ---------------------------------------------------------------------------
  # Extracted so both aws:provision_s3_buckets (app + xtrabackup buckets) and
  # aws:provision_pulumi_state_bucket (Pulumi state) share one implementation.
  #
  # FOLLOW-UP: provision_s3_buckets still carries its own inline copies of
  # ensure_bucket! / ensure_replication_role! / ensure_replication!. They are
  # behaviourally identical to these (the defaults below were chosen to match).
  # Converge that task onto these helpers next time someone is in it with a
  # reason to re-test it — it provisions live app buckets, so it is not worth
  # refactoring blind.

  # Which region each primary region fails over to. Mirrors the xtrabackup
  # bucket layout and AWS_S3_REPLICA_REGION in .env.production.*.
  S3_DR_REGION_PAIRS = {
    "ap-south-1" => "ap-south-2",
    "us-east-1"  => "us-east-2"
  }.freeze

  # Create the bucket if absent, then enforce versioning (mandatory: it is both
  # the backup story and a hard prerequisite for replication on BOTH ends),
  # encryption and public-access-block.
  def s3_ensure_bucket!(client:, bucket:, region:, encrypt: true, block_public: true)
    begin
      client.head_bucket(bucket: bucket)
      puts "✅ Bucket '#{bucket}' already exists in region #{region}."
    rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchBucket
      if region == "us-east-1"
        client.create_bucket(bucket: bucket)
      else
        client.create_bucket(
          bucket: bucket,
          create_bucket_configuration: { location_constraint: region }
        )
      end
      client.wait_until(:bucket_exists, bucket: bucket)
      puts "🪣 Created bucket '#{bucket}' in #{region}."
    rescue Aws::S3::Errors::Http301Error => e
      actual = (e.context.http_response.headers["x-amz-bucket-region"] rescue nil)
      raise "Bucket '#{bucket}' exists in region '#{actual}'. Use a client in that region."
    end

    client.put_bucket_versioning(
      bucket: bucket,
      versioning_configuration: { status: "Enabled" }
    )
    puts "📜 Enabled versioning on '#{bucket}'."

    if encrypt
      client.put_bucket_encryption(
        bucket: bucket,
        server_side_encryption_configuration: {
          rules: [{ apply_server_side_encryption_by_default: { sse_algorithm: "AES256" } }]
        }
      )
    end

    if block_public
      client.put_public_access_block(
        bucket: bucket,
        public_access_block_configuration: {
          block_public_acls: true, ignore_public_acls: true,
          block_public_policy: true, restrict_public_buckets: true
        }
      )
    end
    puts "🔒 Encryption + public-access-block ensured on '#{bucket}'." if encrypt || block_public
  end

  # Idempotent: create_role is guarded, put_role_policy is an upsert.
  def s3_ensure_replication_role!(iam:, role_name:, source_buckets:, dest_buckets:)
    trust_policy = {
      Version: "2012-10-17",
      Statement: [{ Effect: "Allow", Principal: { Service: "s3.amazonaws.com" }, Action: "sts:AssumeRole" }]
    }
    begin
      iam.create_role(role_name: role_name, assume_role_policy_document: trust_policy.to_json)
      puts "🔐 Created S3 replication role '#{role_name}'."
    rescue Aws::IAM::Errors::EntityAlreadyExists
      puts "✅ Replication role '#{role_name}' already exists."
    end

    permission_policy = {
      Version: "2012-10-17",
      Statement: [
        { Effect: "Allow",
          Action: ["s3:GetReplicationConfiguration", "s3:ListBucket"],
          Resource: source_buckets.map { |b| "arn:aws:s3:::#{b}" } },
        { Effect: "Allow",
          Action: ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging",
                   # Needed to replicate into an Object Lock (replica) bucket - fix-backups-deletable
                   *Dr::BackupLock::REPLICATION_ROLE_ACTIONS],
          Resource: source_buckets.map { |b| "arn:aws:s3:::#{b}/*" } },
        { Effect: "Allow",
          Action: ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"],
          Resource: dest_buckets.map { |b| "arn:aws:s3:::#{b}/*" } }
      ]
    }
    iam.put_role_policy(role_name: role_name, policy_name: "s3-replication", policy_document: permission_policy.to_json)
    iam.get_role(role_name: role_name).role.arn
  end

  # --- Checks through the load balancer (end of a recovery) --------------------

  # The app host users type: app.<domain> on production, dev.<domain> on staging, from the
  # target stack's Pulumi config (same convention as aws:dns_cutover)
  def dr_app_host(stack, region)
    require "yaml"
    stack_file = "../IRM-Infra/Pulumi.#{stack}-#{region}.yaml"
    raise "#{stack_file} not found" unless File.exist?(stack_file)

    domain = YAML.load_file(stack_file).dig("config", "IRM-infra:domain_name") or
      raise "domain_name missing in #{stack_file}"
    "#{stack == 'production' ? 'app' : 'dev'}.#{domain.delete_prefix('*.')}"
  end

  # dr:verify runs ON the app servers, so it never touches what users actually hit: the load
  # balancer, its certificate and its target groups. These run from here, against the new load
  # balancer, BEFORE any DNS change: the app host is pinned to the load balancer's address
  # (curl --resolve), so the certificate is checked for real (no -k) and nothing depends on DNS.
  # Printed as a "dr:verify on load-balancer" scorecard so the run report shows them
  # (parse_verify_scorecard). Returns the number of failed checks.
  def dr_edge_checks(stack, region)
    require "resolv"
    require "aws-sdk-elasticloadbalancingv2"
    host = dr_app_host(stack, region)
    out, err, status = Open3.capture3("pulumi stack output --json --stack #{stack}-#{region}", chdir: "../IRM-Infra")
    raise "pulumi stack output failed for #{stack}-#{region}: #{err.lines.last(2).join.strip}" unless status.success?

    alb_dns = JSON.parse(out).dig("alb", "dns_name") or raise "Stack #{stack}-#{region} has no 'alb' output"
    ip = Resolv.getaddress(alb_dns)

    results = []
    check = lambda do |label, grade|
      results << grade.status
      icon = { ok: "✅", warn: "⚠️", fail: "❌" }[grade.status]
      puts "#{icon} #{label} — #{grade.detail}"
    end
    # One HTTPS request to the app host, pinned to the load balancer. Retries: target
    # registration can trail the app's own restart by a few seconds.
    https = lambda do |path|
      body = code = nil
      exit_code = 0
      6.times do |i|
        o, _e, st = Open3.capture3("curl", "-s", "--max-time", "30", "--resolve", "#{host}:443:#{ip}",
                                   "-w", "\n%{http_code}", "https://#{host}#{path}")
        exit_code = st.exitstatus
        body, _, code = o.rpartition("\n")
        break if exit_code.zero? && code == "200"
        break if [51, 60].include?(exit_code) # a certificate problem will not fix itself

        sleep 5 if i < 5
      end
      [exit_code, code, body]
    end

    puts "🩺 dr:verify on load-balancer (#{alb_dns} → #{ip}, Host: #{host})"
    # 1. Certificate + load balancer → app → database (one request proves both)
    exit_code, code, = https.call("/health_check/db_check.json")
    check.call("Load balancer certificate (#{host})", Dr::ServingChecks.grade_certificate(curl_exit: exit_code, host: host))
    check.call("Load balancer → app → database",
               Dr::ServingChecks.grade_edge_http(code: code, what: "a request reaches the app and the database"))
    # 2. Every app server healthy in the load balancer's eyes
    elb = Aws::ElasticLoadBalancingV2::Client.new(region: region)
    lb = elb.describe_load_balancers.load_balancers.find { |l| l.dns_name.casecmp?(alb_dns) }
    states = []
    if lb
      elb.describe_target_groups(load_balancer_arn: lb.load_balancer_arn).target_groups.each do |tg|
        states.concat(elb.describe_target_health(target_group_arn: tg.target_group_arn)
                         .target_health_descriptions.map { |d| d.target_health.state })
      end
    end
    check.call("Load balancer targets healthy", Dr::ServingChecks.grade_targets(healthy: states.count("healthy"), total: states.size))
    # 3. A real screen through the load balancer
    _exit, code, body = https.call("/users/sign_in")
    check.call("Load balancer sign-in page",
               Dr::ServingChecks.grade_edge_http(code: code, body: body, marker: Dr::ServingChecks::SIGN_IN_MARKER,
                                                 what: "the sign-in page loads over HTTPS"))

    fails = results.count(:fail)
    warns = results.count(:warn)
    puts "\n#{fails.zero? ? '🟢' : '🔴'} dr:verify — #{results.size} checks: #{results.size - fails - warns} ok, #{warns} warnings, #{fails} failures"
    fails
  end

  # --- Replica Object Lock (openspec fix-backups-deletable) ---------------------

  # The env's replica buckets, read from where its primaries ACTUALLY replicate
  # (backups "<AWS_S3_BUCKET>-backup-xtra" and documents "<AWS_S3_BUCKET>"), each
  # with its region. Primaries are excluded by construction (Dr::BackupLock).
  def replica_buckets_for_env
    require "aws-sdk-s3"
    primary_docs = ENV.fetch("AWS_S3_BUCKET")
    primaries = ["#{primary_docs}-backup-xtra", primary_docs]
    source = Aws::S3::Client.new(region: ENV.fetch("AWS_S3_REGION"))
    destinations = primaries.flat_map do |bucket|
      rules = source.get_bucket_replication(bucket: bucket).replication_configuration.rules
      rules.select { |r| r.status == "Enabled" }.map { |r| r.destination.bucket.delete_prefix("arn:aws:s3:::") }
    rescue Aws::S3::Errors::ReplicationConfigurationNotFoundError
      []
    end
    Dr::BackupLock.replicas_to_lock(primaries: primaries, destinations: destinations).map do |bucket|
      region = source.get_bucket_location(bucket: bucket).location_constraint.to_s
      { bucket: bucket, region: region.empty? ? "us-east-1" : region }
    end
  end

  # Enables Object Lock on an existing (versioned) replica bucket and sets the
  # default COMPLIANCE retention, per Dr::BackupLock.plan. Idempotent. Turning
  # Object Lock on is PERMANENT, and compliance-locked versions cannot be removed
  # early by anyone - callers must have the user's go-ahead (execute: true).
  def s3_ensure_object_lock!(client:, bucket:, days: Dr::BackupLock::DAYS, execute: false)
    plan = Dr::BackupLock.plan(Dr::BackupLock.read_config(client, bucket), days: days)
    puts "   #{bucket}: #{plan[:summary]}"
    return plan if plan[:action] == :none || !execute

    client.put_object_lock_configuration(
      bucket: bucket,
      object_lock_configuration: {
        object_lock_enabled: "Enabled",
        rule: { default_retention: { mode: Dr::BackupLock::MODE, days: days } }
      }
    )
    after = Dr::BackupLock.read_config(client, bucket)
    raise "#{bucket}: lock not in place after applying (#{after.inspect})" unless Dr::BackupLock.strong_enough?(after, days)

    puts "   🔒 #{bucket}: #{Dr::BackupLock::MODE}, #{days} days — verified"
    plan
  end

  # Configure source -> dest replication.
  #
  # replicate_delete_markers defaults to FALSE: a bad delete (or ransomware) on
  # the source must not propagate to the DR copy. The cost is that the
  # destination can retain objects the source no longer has — deliberate.
  #
  # replication_time_control adds the 15-minute replication SLA plus CloudWatch
  # metrics. Worth it where replication lag is the main risk and data volume is
  # small (Pulumi state); pointless cost on multi-TB backup buckets.
  #
  # Never clobbers by default: an existing config is reported and left alone,
  # because already-live regions have hand-tuned rules. Pass overwrite: true to
  # replace one deliberately (e.g. to add RTC to a rule created without it).
  def s3_ensure_replication!(client:, source_bucket:, dest_bucket:, role_arn:,
                             rule_id: "irm-replicate-all",
                             replicate_delete_markers: false,
                             replication_time_control: false,
                             overwrite: false)
    if source_bucket == dest_bucket
      puts "⚠️  Skipping replication for '#{source_bucket}': destination equals source."
      puts "   A distinct replica bucket in a different region is required for DR to mean anything."
      return false
    end

    dest_arn = "arn:aws:s3:::#{dest_bucket}"
    begin
      existing = client.get_bucket_replication(bucket: source_bucket).replication_configuration
      existing_dests = existing.rules.map { |r| r.destination.bucket }
      if existing_dests.include?(dest_arn) && !overwrite
        puts "✅ Replication #{source_bucket} → #{dest_bucket} already configured — leaving as-is."
        puts "   (pass overwrite: true to rewrite the rule, e.g. to add Replication Time Control)"
        return true
      elsif !existing_dests.include?(dest_arn) && !overwrite
        puts "⚠️  #{source_bucket} already replicates to #{existing_dests.join(', ')} but not to #{dest_bucket}."
        puts "   Not overwriting an existing replication config — reconcile manually if this is unexpected."
        return false
      end
    rescue Aws::S3::Errors::ReplicationConfigurationNotFoundError
      # No config yet — fall through and create it
    end

    destination = { bucket: dest_arn }
    if replication_time_control
      destination[:replication_time] = { status: "Enabled", time: { minutes: 15 } }
      destination[:metrics]          = { status: "Enabled", event_threshold: { minutes: 15 } }
    end

    client.put_bucket_replication(
      bucket: source_bucket,
      replication_configuration: {
        role: role_arn,
        rules: [{
          id: rule_id,
          status: "Enabled",
          priority: 1,
          delete_marker_replication: { status: replicate_delete_markers ? "Enabled" : "Disabled" },
          filter: {}, # whole bucket
          destination: destination
        }]
      }
    )
    puts "🔁 Replication configured: #{source_bucket} → #{dest_bucket} (RTC=#{replication_time_control})."
    puts "   ℹ️  Replication covers NEW objects only — backfill existing ones with"
    puts "   aws s3 sync s3://#{source_bucket} s3://#{dest_bucket} (or S3 Batch Replication)."
    true
  end

  # ---------------------------------------------------------------------------
  # Pulumi state backend preflight
  # ---------------------------------------------------------------------------
  # Every rake task that shells out to pulumi does so with `chdir: "../IRM-Infra"`
  # and inherits whatever backend the operator happens to be logged into, plus
  # whatever is (or is not) in PULUMI_CONFIG_PASSPHRASE. Before the S3 migration
  # that was harmless. After it, two things can go wrong silently:
  #
  #   1. You are logged into a DIFFERENT env's state bucket. Every pulumi read
  #      then describes the wrong environment — during a DR drill, the one you
  #      are not recovering. This must be fatal.
  #   2. The passphrase is unset, so `stack export`, `stack output`, `config
  #      get`, `preview` and `up` all fail partway through a drill.
  #
  # Being logged into Pulumi Cloud is NOT an error: production is migrated after
  # staging, so both backends are legitimate during the transition. Warn and
  # carry on.

  PULUMI_STATE_PRIMARY_REGIONS = { "in" => "ap-south-1", "us" => "us-east-1" }.freeze

  # The bucket pair for an env. Single source of truth — aws:provision_pulumi_state_bucket
  # creates exactly these names, and migrate_state_to_s3.sh expects them.
  def pulumi_state_buckets(env_name)
    account, geo = env_name.to_s.split(".")
    primary_region = PULUMI_STATE_PRIMARY_REGIONS[geo] or
      raise "No primary region known for geography '#{geo}' (env '#{env_name}')"
    dr_region = S3_DR_REGION_PAIRS[primary_region]
    {
      primary_region: primary_region,
      dr_region: dr_region,
      primary: "irm-pulumi-state-#{account}-primary-#{primary_region}",
      replica: "irm-pulumi-state-#{account}-replica-#{dr_region}"
    }
  end

  # The lock files Pulumi currently holds for one stack in the S3 backend, as
  # JSON strings (pid, username, hostname, timestamp). Pulumi writes one per
  # running update under .pulumi/locks/<org>/<project>/<stack>/<id>.json and
  # deletes it when the update ends — so a file left behind is a stale lock.
  # Read-only. Used by aws:dr_drill to refuse BEFORE `pulumi up` (Dr::PulumiLock).
  def pulumi_stack_lock_files(env_name, stack_name)
    require "aws-sdk-s3" # explicit: aws:dr_drill runs without the Rails environment
    buckets = pulumi_state_buckets(env_name)
    s3 = Aws::S3::Client.new(region: buckets[:primary_region])
    keys = []
    s3.list_objects_v2(bucket: buckets[:primary], prefix: ".pulumi/locks/").each_page do |page|
      keys.concat(page.contents.map(&:key).select { |k| k.include?("/#{stack_name}/") && k.end_with?(".json") })
    end
    keys.map { |key| s3.get_object(bucket: buckets[:primary], key: key).body.read }
  end

  # Current pulumi backend URL, or nil if it cannot be determined.
  def pulumi_current_backend
    out, = Open3.capture3("pulumi whoami --verbose", chdir: "../IRM-Infra")
    line = out.lines.grep(/Backend URL/i).first
    line && line.split(/URL:?\s*/i).last.to_s.strip
  rescue StandardError
    nil
  end

  # Load the state passphrase into this process's environment.
  #
  # Precedence:
  #   1. an already-exported PULUMI_CONFIG_PASSPHRASE — an operator overriding
  #      deliberately always wins
  #   2. the env's Rails credentials, decrypted the same way aws:environment
  #      decrypts the AWS keys, so a drill needs nothing but the .key file
  #   3. SSM /irm/pulumi/passphrase, the cross-region source of truth
  #      (PULUMI_STATE.md) — the fallback for a machine without the .key
  def load_pulumi_passphrase!(env_name, region)
    return :already_set unless ENV["PULUMI_CONFIG_PASSPHRASE"].to_s.empty?

    from_credentials = pulumi_passphrase_from_credentials(env_name)
    if from_credentials
      ENV["PULUMI_CONFIG_PASSPHRASE"] = from_credentials
      return :credentials
    end

    # Per-env parameter: production.in and production.us share an AWS account
    # but are separately encrypted. The legacy account-wide path is still read
    # as a fallback for envs migrated before the split.
    require "aws-sdk-ssm"
    ssm = Aws::SSM::Client.new(region: region)
    value = nil
    ["/irm/pulumi/passphrase/#{env_name}", "/irm/pulumi/passphrase"].each do |name|
      begin
        value = ssm.get_parameter(name: name, with_decryption: true).parameter.value
        break
      rescue Aws::SSM::Errors::ParameterNotFound
        next
      end
    end
    raise "no passphrase parameter found in SSM (#{region})" if value.nil?

    ENV["PULUMI_CONFIG_PASSPHRASE"] = value
    :ssm
  rescue StandardError => e
    raise "PULUMI_CONFIG_PASSPHRASE is not set, is absent from config/credentials/#{env_name}.yml.enc, " \
          "and could not be read from SSM /irm/pulumi/passphrase/#{env_name} in #{region}: #{e.message}\n" \
          "   Export it manually:\n" \
          "     export PULUMI_CONFIG_PASSPHRASE=$(aws ssm get-parameter --name /irm/pulumi/passphrase/#{env_name} \\\n" \
          "       --with-decryption --region #{region} --query Parameter.Value --output text)"
  end

  # Returns the passphrase from the env's encrypted credentials, or nil if the
  # file, key or entry is absent. Never raises: a missing entry is expected
  # before the key has been added, and SSM is the fallback.
  def pulumi_passphrase_from_credentials(env_name)
    key_path = Rails.root.join("config", "credentials", "#{env_name}.key")
    enc_path = Rails.root.join("config", "credentials", "#{env_name}.yml.enc")
    return nil unless File.exist?(key_path) && File.exist?(enc_path)

    creds = Rails.application.encrypted(enc_path, key_path: key_path)
    value = creds[:PULUMI_CONFIG_PASSPHRASE] || creds[:pulumi_config_passphrase]
    value.to_s.empty? ? nil : value.to_s
  rescue StandardError
    nil
  end

  # Does the env's primary state bucket exist yet? That is how we tell a
  # migrated env from one still on Pulumi Cloud, without hardcoding a list that
  # would go stale as each env moves.
  def pulumi_state_bucket_exists?(bucket, region)
    require "aws-sdk-s3"
    Aws::S3::Client.new(region: region).head_bucket(bucket: bucket)
    true
  rescue StandardError
    false
  end

  def pulumi_login!(target)
    out, err, st = Open3.capture3("pulumi login #{target}", chdir: "../IRM-Infra")
    return true if st.success?

    raise "pulumi login #{target} failed: #{(err.to_s + out.to_s).lines.first.to_s.strip}"
  end

  # Call at the start of any task that shells out to pulumi.
  #
  # Logs in to the env's state bucket itself rather than telling the operator to
  # — the task knows exactly which bucket it needs, so making a human retype it
  # only creates a chance to get it wrong. Two cases are NOT auto-corrected:
  #
  #   * the replica bucket, which someone may be on deliberately during a real
  #     failover; switching them to a primary in a dead region would break
  #     incident response. Requires PULUMI_ALLOW_REPLICA=true to proceed.
  #   * an env with no state bucket yet, i.e. not migrated. Stays on Pulumi
  #     Cloud with a warning.
  #
  # PULUMI_NO_AUTO_LOGIN=true turns the switch back into an instruction.
  def ensure_pulumi_backend!(env_name, fatal: true)
    buckets = pulumi_state_buckets(env_name)
    backend = pulumi_current_backend

    if backend.to_s.empty?
      raise "Could not determine the Pulumi backend (`pulumi whoami` failed in ../IRM-Infra). " \
            "Is the Pulumi CLI installed and logged in?"
    end

    current_bucket = backend.start_with?("s3://") ? backend.sub(%r{\As3://}, "").split("?").first : nil

    if current_bucket == buckets[:replica]
      if ENV["PULUMI_ALLOW_REPLICA"] == "true"
        puts "⚠️  Using the REPLICA bucket #{current_bucket} (PULUMI_ALLOW_REPLICA=true)."
        puts "   Only correct during a real #{buckets[:primary_region]} outage — see IRM-Infra/PULUMI_STATE.md."
        load_pulumi_passphrase!(env_name, buckets[:dr_region])
        return :replica
      end
      raise "Pulumi is logged into the REPLICA bucket #{current_bucket}, which is read-only " \
            "outside a real #{buckets[:primary_region]} outage; writing to it creates " \
            "split-brain state (IRM-Infra/PULUMI_STATE.md).\n" \
            "   Not switching automatically, in case this is a deliberate failover.\n" \
            "   Normal operation: pulumi login \"s3://#{buckets[:primary]}?region=#{buckets[:primary_region]}\"\n" \
            "   Real failover:    re-run with PULUMI_ALLOW_REPLICA=true"
    end

    if current_bucket != buckets[:primary]
      target = "\"s3://#{buckets[:primary]}?region=#{buckets[:primary_region]}\""

      unless pulumi_state_bucket_exists?(buckets[:primary], buckets[:primary_region])
        puts "⚠️  Pulumi backend is #{backend}; #{env_name} has no state bucket yet"
        puts "   (#{buckets[:primary]} does not exist), so it is still on Pulumi Cloud."
        puts "   Migrate with: IRM-Infra/migrate_state_to_s3.sh #{env_name}"
        return :cloud
      end

      if ENV["PULUMI_NO_AUTO_LOGIN"] == "true"
        raise "Pulumi backend is #{backend}, but #{env_name} state lives in #{buckets[:primary]}.\n" \
              "   Run: pulumi login #{target}"
      end

      puts "🔀 Switching Pulumi backend: #{backend} → s3://#{buckets[:primary]}"
      pulumi_login!(target)

      now = pulumi_current_backend.to_s
      unless now.sub(%r{\As3://}, "").split("?").first == buckets[:primary]
        raise "Tried to switch to #{buckets[:primary]} but the backend is now '#{now}'."
      end
    end

    case load_pulumi_passphrase!(env_name, buckets[:primary_region])
    when :credentials
      puts "🔑 PULUMI_CONFIG_PASSPHRASE loaded from config/credentials/#{env_name}.yml.enc"
    when :ssm
      puts "🔑 PULUMI_CONFIG_PASSPHRASE loaded from SSM (#{buckets[:primary_region]})"
    end
    puts "✅ Pulumi backend: s3://#{buckets[:primary]} (#{buckets[:primary_region]})"
    :s3
  rescue StandardError => e
    raise if fatal

    puts "⚠️  Pulumi backend preflight: #{e.message.lines.first.to_s.strip}"
    :error
  end
end
