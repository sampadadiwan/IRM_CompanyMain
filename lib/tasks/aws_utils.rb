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
      [stdout, stderr].map do |io|
        Thread.new do
          io.each_line { |line| lock.synchronize { puts line.chomp } }
        end
      end.each(&:join)

      exit_status = wait_thr.value
      unless exit_status.success?
        raise "Command failed with status #{exit_status.exitstatus}: #{command}"
      end
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


    puts "✨ Latest AMI found: #{latest_ami.image_id} with name: #{latest_ami.name}, date: #{latest_ami.creation_date}"
    latest_ami
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
      "IRM-infra:web_server_ami" => latest_ami(web_server_name, region).image_id,
      "IRM-infra:db_server_ami" => latest_ami(db_server_name, region).image_id,
      "IRM-infra:observability_ami" => latest_ami("Observability", region).image_id
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

  # Runs the block with stdout/stderr duplicated into docs/dr_runs/<name>.log.
  # The transcript is the blow-by-blow record behind the evidence report:
  # write_dr_report indexes independently verifiable claims, this is what
  # actually happened, line by line.
  def with_dr_transcript(name)
    path = Rails.root.join("docs", "dr_runs", "#{name}.log")
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

  # Writes the per-run evidence document.
  #
  # Deliberately NOT a self-contained narrative: a markdown file a script writes
  # about itself is a claim, not proof, and the first thing an auditor asks is
  # what stopped someone editing it. So every factual claim is either (a) tied
  # to a record held OUTSIDE this repo with the command that checks it, or
  # (b) reproduced verbatim from the run's own transcript. What the report adds
  # is legibility — an auditor should not have to read 40,000 lines of
  # Capistrano output to see that 22 checks passed on two hosts.
  # Stylesheet for the HTML evidence record. Kept as a constant so the builder
  # below stays readable — it is a document, not a template engine.
  # Light-first with a full dark-theme token set: an auditor may read this in
  # either, and a report that renders unreadably undermines the thing it exists
  # to prove.
  DR_REPORT_CSS = <<~CSS
    :root{--paper:#F6F7F9;--surface:#FFF;--surface-2:#EFF2F5;--ink:#111820;--ink-soft:#566274;--ink-faint:#8894A3;--rule:#DCE1E7;--rule-firm:#C3CBD4;--verified:#16694A;--verified-bg:#E4F0EA;--caution:#8A5C0D;--caution-bg:#F7EEDC;--accent:#0F4C5C;--accent-soft:#E2EDF0;--serif:"IBM Plex Serif",Georgia,serif;--sans:"IBM Plex Sans",system-ui,-apple-system,"Segoe UI",sans-serif;--mono:"IBM Plex Mono",ui-monospace,Menlo,Consolas,monospace}
    @media(prefers-color-scheme:dark){:root:not([data-theme="light"]){--paper:#0C1116;--surface:#131A21;--surface-2:#1A222B;--ink:#E4EBF2;--ink-soft:#98A5B3;--ink-faint:#6B7885;--rule:#232D37;--rule-firm:#33404C;--verified:#46BC8B;--verified-bg:#12291F;--caution:#DCA646;--caution-bg:#2A2113;--accent:#58B3C7;--accent-soft:#122730}}
    :root[data-theme="dark"]{--paper:#0C1116;--surface:#131A21;--surface-2:#1A222B;--ink:#E4EBF2;--ink-soft:#98A5B3;--ink-faint:#6B7885;--rule:#232D37;--rule-firm:#33404C;--verified:#46BC8B;--verified-bg:#12291F;--caution:#DCA646;--caution-bg:#2A2113;--accent:#58B3C7;--accent-soft:#122730}
    *{box-sizing:border-box}
    body{background:var(--paper);color:var(--ink);font-family:var(--sans);font-size:15px;line-height:1.6;-webkit-font-smoothing:antialiased}
    .sheet{max-width:1080px;margin:0 auto;padding:48px 28px 96px;display:flex;flex-direction:column;gap:52px}
    .masthead{border-top:3px solid var(--ink);border-bottom:1px solid var(--rule-firm);padding:22px 0 26px;display:flex;flex-direction:column;gap:20px}
    .eyebrow{font-family:var(--mono);font-size:11px;font-weight:500;letter-spacing:.16em;text-transform:uppercase;color:var(--ink-faint);display:flex;flex-wrap:wrap;gap:8px 18px}
    .masthead h1{font-family:var(--serif);font-weight:600;font-size:clamp(30px,5vw,44px);line-height:1.1;letter-spacing:-.015em;margin:0;text-wrap:balance}
    .subject{font-family:var(--mono);font-size:15px;color:var(--ink-soft);display:flex;flex-wrap:wrap;align-items:center;gap:10px}
    .subject strong{color:var(--ink);font-weight:600}.subject .arrow{color:var(--ink-faint)}
    .verdict{display:inline-flex;align-items:center;gap:10px;align-self:flex-start;border-radius:2px;padding:7px 14px 7px 11px;font-family:var(--mono);font-size:13px;font-weight:600;letter-spacing:.1em;text-transform:uppercase}
    .verdict.pass{background:var(--verified-bg);color:var(--verified);border:1px solid color-mix(in srgb,var(--verified) 35%,transparent)}
    .verdict.fail{background:var(--caution-bg);color:var(--caution);border:1px solid color-mix(in srgb,var(--caution) 45%,transparent)}
    .verdict .tick{width:16px;height:16px;display:grid;place-items:center;border-radius:50%;font-size:10px;font-weight:700}
    .verdict.pass .tick{background:var(--verified);color:var(--verified-bg)}.verdict.fail .tick{background:var(--caution);color:var(--caution-bg)}
    .metrics{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:1px;background:var(--rule);border:1px solid var(--rule);border-radius:3px;overflow:hidden}
    .metric{background:var(--surface);padding:18px 20px 20px;display:flex;flex-direction:column;gap:6px}
    .metric dt{font-family:var(--mono);font-size:10px;letter-spacing:.14em;text-transform:uppercase;color:var(--ink-faint)}
    .metric dd{margin:0;font-family:var(--mono);font-size:28px;font-weight:600;letter-spacing:-.02em;font-variant-numeric:tabular-nums;color:var(--ink)}
    .metric .qualifier{font-family:var(--sans);font-size:12px;color:var(--ink-soft)}
    section{display:flex;flex-direction:column;gap:18px}
    h2{font-family:var(--serif);font-size:21px;font-weight:600;margin:0;letter-spacing:-.01em;display:flex;align-items:baseline;gap:12px}
    h2::after{content:"";flex:1;height:1px;background:var(--rule)}
    .lede{max-width:66ch;color:var(--ink-soft);margin:0;font-size:14.5px}
    .scroll{overflow-x:auto;border:1px solid var(--rule);border-radius:3px;background:var(--surface)}
    table{border-collapse:collapse;width:100%;font-size:13.5px}
    th,td{text-align:left;padding:10px 14px;border-bottom:1px solid var(--rule);vertical-align:top}
    thead th{font-family:var(--mono);font-size:10px;letter-spacing:.13em;text-transform:uppercase;color:var(--ink-faint);font-weight:500;background:var(--surface-2);border-bottom:1px solid var(--rule-firm);white-space:nowrap}
    tbody tr:last-child td{border-bottom:none}
    .num{font-family:var(--mono);font-variant-numeric:tabular-nums;white-space:nowrap}
    .key{color:var(--ink-soft);width:190px}
    .val{font-family:var(--mono);font-variant-numeric:tabular-nums}
    code{font-family:var(--mono);font-size:.93em;background:var(--surface-2);border:1px solid var(--rule);border-radius:2px;padding:1px 5px;word-break:break-word}
    .mark{display:inline-grid;place-items:center;width:18px;height:18px;border-radius:50%;font-family:var(--mono);font-size:10px;font-weight:700;line-height:1}
    .mark.pass{background:var(--verified-bg);color:var(--verified);border:1px solid color-mix(in srgb,var(--verified) 40%,transparent)}
    .mark.warn{background:var(--caution-bg);color:var(--caution);border:1px solid color-mix(in srgb,var(--caution) 40%,transparent)}
    .mark.fail{background:var(--caution-bg);color:var(--caution);border:1px solid var(--caution)}
    td.markcell{width:40px;text-align:center;padding-top:11px}
    .phase-name{font-weight:500}
    .bar{display:block;height:6px;border-radius:1px;background:var(--accent);min-width:2px;margin-top:7px;opacity:.85}
    .bar.dominant{background:var(--verified)}
    .barcell{width:34%;min-width:150px}
    .seq{font-family:var(--mono);font-size:11px;color:var(--ink-faint);font-variant-numeric:tabular-nums}
    .host{border:1px solid var(--rule);border-radius:3px;background:var(--surface);overflow:hidden}
    .host-head{display:flex;flex-wrap:wrap;align-items:baseline;justify-content:space-between;gap:10px;padding:13px 16px;background:var(--surface-2);border-bottom:1px solid var(--rule-firm)}
    .host-head .name{font-family:var(--mono);font-weight:600;font-size:13.5px}
    .host-head .tally{font-family:var(--mono);font-size:12px;color:var(--ink-soft);font-variant-numeric:tabular-nums}
    .host .scroll{border:none;border-radius:0}
    .hosts{display:grid;gap:20px;grid-template-columns:repeat(auto-fit,minmax(430px,1fr))}
    .scope{border:1px solid var(--rule-firm);border-radius:3px;background:var(--surface);overflow:hidden}
    .scope-row{display:grid;grid-template-columns:132px 1fr;border-bottom:1px solid var(--rule)}
    .scope-row:last-child{border-bottom:none}
    .scope-label{padding:15px 16px;font-family:var(--mono);font-size:11px;letter-spacing:.12em;text-transform:uppercase;background:var(--surface-2);border-right:1px solid var(--rule)}
    .scope-label.in{color:var(--verified)}.scope-label.out{color:var(--caution)}
    .scope-body{padding:15px 18px;font-size:14px}
    .scope-note{margin:0;padding:14px 18px;background:var(--accent-soft);border-top:1px solid var(--rule);font-size:14px}
    footer{border-top:1px solid var(--rule-firm);padding-top:18px;font-family:var(--mono);font-size:11.5px;color:var(--ink-faint);display:flex;flex-wrap:wrap;gap:6px 20px;justify-content:space-between}
    a{color:var(--accent);text-underline-offset:2px}
    a:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
    @media(max-width:620px){.sheet{padding:32px 16px 64px;gap:40px}.key{width:auto}.scope-row{grid-template-columns:1fr}.scope-label{border-right:none;border-bottom:1px solid var(--rule)}}
  CSS

  def h(text) # minimal HTML escape — report data is our own output, not user input
    text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
  end

  # Renders the same evidence as the markdown report as a self-contained HTML
  # page, so it can be handed to an auditor (or printed to PDF) without them
  # needing a markdown renderer or a checkout of this repository.
  def write_dr_report_html(stack:, region:, env_variant:, branch:, result:, started_at:, finished:,
                           scorecard:, drill:)
    rebuild_secs = (finished - started_at).round
    passed = result.to_s.match?(/PASSED|COMPLETE/)
    all_checks = scorecard.values.flatten(1)
    ok_count   = all_checks.count { |icon, _| icon == "✅" }
    warn_count = all_checks.count { |icon, _| icon == "⚠️" }
    fail_count = all_checks.count { |icon, _| icon == "❌" }
    db_phase = DR_PHASES.find { |t, _, _| t.include?("Restore the database") }
    db_secs  = db_phase && ((db_phase[2] || finished) - db_phase[1]).round
    freshness = all_checks.find { |_, t| t.start_with?("Restored data freshness") }&.last.to_s[/is (.+?)$/, 1]
    total = [rebuild_secs, 1].max

    metric = lambda do |label, value, qualifier|
      %(<div class="metric"><dt>#{h label}</dt><dd>#{value}</dd><span class="qualifier">#{h qualifier}</span></div>)
    end

    phase_rows = DR_PHASES.map.with_index(1) do |(title, s, e), i|
      secs  = ((e || finished) - s).round
      share = (secs * 100.0 / total).round(1)
      name  = title.sub(%r{\APhase \d+/\d+ · }, "")
      <<~ROW
        <tr><td class="markcell"><span class="mark #{e ? 'pass' : 'warn'}">#{e ? '&check;' : '!'}</span></td>
        <td class="seq">#{i}</td><td class="phase-name">#{h name}</td>
        <td class="num">#{s.utc.strftime('%H:%M:%S')}</td><td class="num">#{(e || finished).utc.strftime('%H:%M:%S')}</td>
        <td class="num">#{hms(secs)}</td>
        <td class="barcell"><span class="bar#{' dominant' if share > 40}" style="width:#{[share, 100].min}%"></span></td></tr>
      ROW
    end.join

    host_blocks = if scorecard.empty?
                    %(<p class="lede">No verification scorecard was captured — this run did not reach the verification stage.</p>)
                  else
                    scorecard.map do |host, checks|
                      rows = checks.map do |icon, text|
                        name, detail = text.split(" — ", 2)
                        css = { "✅" => "pass", "⚠️" => "warn", "❌" => "fail" }[icon] || "warn"
                        glyph = css == "pass" ? "&check;" : "!"
                        %(<tr><td class="markcell"><span class="mark #{css}">#{glyph}</span></td><td>#{h name}</td><td class="val">#{h(detail || '—')}</td></tr>)
                      end.join
                      ok = checks.count { |i, _| i == "✅" }
                      <<~HOST
                        <div class="host"><div class="host-head">
                        <span class="name">#{h host}</span>
                        <span class="tally">#{ok} passed · #{checks.count { |i, _| i == '⚠️' }} warning · #{checks.count { |i, _| i == '❌' }} failed</span>
                        </div><div class="scroll"><table><tbody>#{rows}</tbody></table></div></div>
                      HOST
                    end.join
                  end

    evidence_rows = DR_EVIDENCE.map do |claim, (ev, how)|
      %(<tr><td>#{h claim}</td><td class="val">#{h ev}</td><td>#{h how}</td></tr>)
    end.join

    particulars = {
      "Environment" => "#{stack} (#{env_variant})",
      "Recovered into" => "#{region}#{drill ? ' — disaster-recovery region' : ''}",
      "Started" => started_at.utc.strftime("%Y-%m-%d %H:%M:%S UTC"),
      "Finished" => finished.utc.strftime("%Y-%m-%d %H:%M:%S UTC"),
      "Rebuild time" => "#{hms(rebuild_secs)} (#{(rebuild_secs / 60.0).round(1)} minutes)",
      "Code deployed" => branch,
      "Executed by" => "#{ENV['USER'] || 'unknown'}@#{`hostname`.strip}"
    }.map { |k, v| %(<tr><td class="key">#{h k}</td><td class="val">#{h v}</td></tr>) }.join

    <<~HTML
      <title>#{drill ? 'Recovery Drill Record' : 'Recovery Record'} — #{h stack}</title>
      <link rel="preconnect" href="https://fonts.googleapis.com">
      <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
      <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Serif:wght@400;600&display=swap">
      <style>#{DR_REPORT_CSS}</style>
      <div class="sheet">
        <header class="masthead">
          <div class="eyebrow"><span>Disaster Recovery Record</span><span>Ref · #{h branch}</span><span>#{started_at.utc.strftime('%d %B %Y')}</span></div>
          <h1>#{passed ? "#{h stack.capitalize} recovery rebuilt and verified in #{hms(rebuild_secs)}" : "#{h stack.capitalize} recovery did not complete"}</h1>
          <div class="subject"><strong>#{h stack}</strong> <span>(#{h env_variant})</span> <span class="arrow">&rarr;</span> <strong>#{h region}</strong></div>
          <span class="verdict #{passed ? 'pass' : 'fail'}"><span class="tick">#{passed ? '&check;' : '!'}</span> #{h result}</span>
        </header>

        <dl class="metrics">
          #{metric.call('Rebuild time', hms(rebuild_secs), 'command start to verified')}
          #{db_secs ? metric.call('Database restore', hms(db_secs), 'primary + replica, in parallel') : ''}
          #{metric.call('Checks passed', %(#{ok_count}<span style="color:var(--ink-faint);font-weight:400">/#{all_checks.size}</span>), "#{warn_count} warning#{'s' if warn_count != 1}, #{fail_count} failure#{'s' if fail_count != 1}")}
          #{freshness ? metric.call('Data currency', h(freshness.split.first), 'age of newest restored record') : ''}
        </dl>

        <section><h2>Run particulars</h2><div class="scroll"><table><tbody>#{particulars}</tbody></table></div>
        #{drill ? %(<p class="lede">Scheduled drill against <strong>#{h stack}</strong> — not a response to a real incident. It exercised the identical code path a real recovery uses.</p>) : ''}
        </section>

        <section><h2>Recovery sequence</h2>
        <p class="lede">Every phase in the order it executed, with wall-clock times. Bars are drawn to scale against the #{hms(rebuild_secs)} total.</p>
        <div class="scroll"><table>
        <thead><tr><th></th><th>#</th><th>Phase</th><th>Start</th><th>End</th><th>Duration</th><th class="barcell">Share of run</th></tr></thead>
        <tbody>#{phase_rows}</tbody></table></div></section>

        <section><h2>Verification scorecard</h2>
        <p class="lede">The recovery is not reported as successful until every one of these checks passes on <em>every</em> application server. Each exercises the real serving path — an HTTP request through nginx to Puma to Rails to the dependency itself — rather than a mock or a status file. Reproduced verbatim from the run transcript.</p>
        <div class="hosts">#{host_blocks}</div></section>

        <section><h2>Independently verifiable evidence</h2>
        <p class="lede">Each row names a record held <em>outside</em> the application repository, together with the command that checks it. Nothing in this document has to be taken on trust.</p>
        <div class="scroll"><table><thead><tr><th>Claim</th><th>Evidence</th><th>How to verify independently</th></tr></thead>
        <tbody>#{evidence_rows}</tbody></table></div></section>

        <section><h2>What the measured time covers</h2>
        <p class="lede">The headline figure is <strong>rebuild time</strong>, not end-to-end recovery time objective. It is measured from the start of the recovery command to the stack passing verification.</p>
        <div class="scope">
          <div class="scope-row"><div class="scope-label in">Included</div><div class="scope-body">Infrastructure provisioning · configuration rewrite · application deploy to every server · database restore from backups, primary and replica in parallel · replication re-pointing · migration replay · the full verification scorecard above.</div></div>
          <div class="scope-row"><div class="scope-label out">Excluded</div><div class="scope-body">Incident detection · the human decision to declare a disaster · DNS cutover and its propagation delay. Cutover is deliberately a manual step and is never performed by the recovery sequence.</div></div>
          <p class="scope-note">A true incident-to-service-restored figure is the time above <strong>plus</strong> those three components. Stated explicitly so the number is not read as more than it is.</p>
        </div></section>

        <section><h2>Source record</h2>
        <p class="lede">Every command issued during this recovery and its complete output — including the raw verification scorecard reproduced above — was captured automatically to <code>docs/dr_runs/#{h branch}.log</code>. This document states what is claimed and how to check it; the transcript records what happened, line by line.</p></section>

        <footer><span>Disaster Recovery Record · #{h stack} (#{h env_variant}) &rarr; #{h region}</span><span>Generated #{finished.utc.iso8601}</span></footer>
      </div>
    HTML
  end

  def write_dr_report(stack:, region:, env_variant:, branch:, result:, started_at:, drill: false)
    finished = Time.now
    rebuild_secs = (finished - started_at).round
    passed = result.to_s.match?(/PASSED|COMPLETE/)
    dir = Rails.root.join("docs", "dr_runs")
    FileUtils.mkdir_p(dir)
    path = dir.join("#{branch}.md")
    transcript = dir.join("#{branch}.log")

    scorecard = parse_verify_scorecard(transcript)
    all_checks = scorecard.values.flatten(1)
    ok_count   = all_checks.count { |icon, _| icon == "✅" }
    warn_count = all_checks.count { |icon, _| icon == "⚠️" }
    fail_count = all_checks.count { |icon, _| icon == "❌" }

    # Headline numbers an auditor looks for first
    db_phase   = DR_PHASES.find { |t, _, _| t.include?("Restore the database") }
    db_secs    = db_phase && ((db_phase[2] || finished) - db_phase[1]).round
    freshness  = all_checks.find { |_, text| text.start_with?("Restored data freshness") }&.last.to_s[/is (.+?)$/, 1]

    banner = passed ? "🟢  RECOVERY SUCCEEDED" : "🔴  RECOVERY FAILED"

    phase_rows = DR_PHASES.map.with_index(1) do |(title, s, e), i|
      done = !e.nil?
      "| #{done ? '✅' : '⏹'} | #{i} | #{title.sub(%r{\APhase \d+/\d+ · }, '')} | #{s.utc.strftime('%H:%M:%S')} | #{(e || finished).utc.strftime('%H:%M:%S')} | **#{hms(((e || finished) - s).round)}** |"
    end.join("\n")

    scorecard_sections = if scorecard.empty?
                           "_No verification scorecard was captured — the run did not reach `recovery:verify`._"
                         else
                           scorecard.map do |host, checks|
                             rows = checks.map { |icon, text|
                               name, detail = text.split(" — ", 2)
                               "| #{icon} | #{name} | #{detail} |"
                             }.join("\n")
                             <<~HOST
                               **Host `#{host}`** — #{checks.count} checks, #{checks.count { |i, _| i == '✅' }} passed

                               | | Check | Result |
                               |:-:|---|---|
                               #{rows}
                             HOST
                           end.join("\n")
                         end

    evidence_rows = DR_EVIDENCE.map { |claim, (ev, how)| "| #{claim} | #{ev} | #{how} |" }.join("\n")

    File.write(path, <<~MD)
      <div align="center">

      # #{banner}

      ### Disaster Recovery #{drill ? 'Drill' : 'Run'} — `#{stack}` (#{env_variant}) → `#{region}`

      **#{hms(rebuild_secs)}** rebuild&nbsp;&nbsp;·&nbsp;&nbsp;**#{ok_count}/#{all_checks.size}** checks passed&nbsp;&nbsp;·&nbsp;&nbsp;**#{DR_PHASES.size}** phases completed#{db_secs ? "&nbsp;&nbsp;·&nbsp;&nbsp;**#{hms(db_secs)}** to restore the database" : ''}

      </div>

      ---

      ## At a glance

      | | |
      |---|---|
      | **Result** | **#{result}** |
      | Environment | `#{stack}` (#{env_variant}) |
      | Recovered into | `#{region}`#{drill ? ' — disaster-recovery region' : ''} |
      | Started | **#{started_at.utc.strftime('%Y-%m-%d %H:%M:%S UTC')}** |
      | Finished | **#{finished.utc.strftime('%Y-%m-%d %H:%M:%S UTC')}** |
      | Rebuild time | **#{hms(rebuild_secs)}** (#{(rebuild_secs / 60.0).round(1)} minutes) |
      #{db_secs ? "| Database restore | **#{hms(db_secs)}** (primary + replica, in parallel) |\n" : ''}| Verification | **#{ok_count} passed**#{warn_count.positive? ? ", #{warn_count} warning#{'s' if warn_count != 1}" : ''}#{fail_count.positive? ? ", **#{fail_count} failed**" : ''} across #{scorecard.size} app server#{'s' if scorecard.size != 1} |
      #{freshness ? "| Data currency | newest restored record is #{freshness} |\n" : ''}| Code deployed | `#{branch}` |
      | Executed by | #{ENV['USER'] || 'unknown'}@#{`hostname`.strip} |
      #{drill ? "\n> ℹ️ This was a **scheduled drill** against `#{stack}`, not a response to a real incident. It exercised the identical code path a real recovery uses.\n" : ''}
      ---

      ## Recovery timeline

      Every phase of the recovery, in order, with wall-clock times.

      | | # | Phase | Start (UTC) | End (UTC) | Duration |
      |:-:|:-:|---|---|---|---|
      #{phase_rows}

      **Total: #{hms(rebuild_secs)}**

      ---

      ## Verification scorecard

      The recovery is not reported as successful until every one of these
      checks passes on **every** application server. Each exercises the real
      serving path — HTTP through nginx to Puma to Rails to the dependency —
      not a mock or a status file. Reproduced verbatim from the run transcript.

      #{scorecard_sections}

      ---

      ## Independently verifiable evidence

      Each row names a record held **outside this repository**. Nothing here
      relies on trusting this document.

      | Claim | Evidence | How to verify independently |
      |---|---|---|
      #{evidence_rows}

      ---

      ## What the measured time covers

      The headline figure is **rebuild time**, not end-to-end RTO — measured
      from the start of the recovery command to the stack passing verification.

      | | |
      |---|---|
      | ✅ **Included** | Infrastructure provisioning, configuration rewrite, application deploy to every app server, database restore from S3 (primary and replica in parallel), replication re-pointing, migration replay, and the full verification scorecard above. |
      | ❌ **Excluded** | Incident detection, the human decision to declare a disaster, and DNS cutover plus TTL propagation — cutover is deliberately manual and is never invoked by the recovery sequence. |

      A true incident-to-service-restored RTO is the figure above **plus** those
      three components. Stated explicitly so the number is not read as more than
      it is.

      ---

      ## Full transcript

      Every command and its complete output — including the raw verification
      scorecard reproduced above — was captured automatically to
      **`docs/dr_runs/#{branch}.log`**. The report says what is claimed and how
      to check it; the transcript says what happened, line by line.

      Re-run verification against a still-running stack at any time:

      ```bash
      LB=true bundle exec cap #{stack}_#{env_variant} recovery:verify
      ```

      ---
      <div align="center">
      <sub>Generated #{finished.utc.iso8601} by <code>#{drill ? 'rake aws:dr_drill' : 'rake aws:setup_infra'}</code></sub>
      </div>
    MD

    puts "🧾 Evidence report written to #{path.to_s.sub("#{Rails.root}/", '')}"

    # HTML alongside the markdown: the auditor-facing copy. Self-contained
    # (styles inline, fonts from Google Fonts, no build step), so it can be
    # opened straight from a filesystem, emailed, or printed to PDF without a
    # markdown renderer or a checkout of this repository.
    html_path = dir.join("#{branch}.html")
    File.write(html_path, write_dr_report_html(
                            stack: stack, region: region, env_variant: env_variant, branch: branch,
                            result: result, started_at: started_at, finished: finished,
                            scorecard: scorecard, drill: drill
                          ))
    puts "📄 Auditor report (HTML) written to #{html_path.to_s.sub("#{Rails.root}/", '')}"

    path
  rescue StandardError => e
    puts "⚠️  Could not write DR report: #{e.class}: #{e.message}"
    nil
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

    dr_phase "Phase 1/8 · Refresh Pulumi stack configuration"
    setup_pulumi_config(stack, web_server_name, db_server_name, region, env_variant)

    dr_phase "Phase 2/8 · Provision infrastructure (pulumi up)"
    puts "⬆️ Running pulumi up for stack: #{stack}. (This could take a long time, please be patient)"
    # Run pulumi to setup the aws infra
    run_cmd("pulumi up --stack #{stack}-#{region} --yes --color=always", "../IRM-Infra")

    if (upd = pulumi_update_record("#{stack}-#{region}"))
      record_dr_evidence("Infrastructure provisioned in #{region}",
                         "Pulumi update ##{upd[:version]} — #{upd[:result]}, #{upd[:started]} → #{upd[:ended]}",
                         "`pulumi stack history --stack #{stack}-#{region}` (server-side record, Pulumi console)")
    end
    # Get the pulumi output

    dr_phase "Phase 3/8 · Rewrite config with the new host addresses"
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
      dr_phase "Phase 4/8 · Commit and push the DR branch (#{branch_name})"
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

    dr_phase "Phase 5/8 · Deploy the application to both app servers"
    # Deploy the app
    run_cmd("branch=#{branch_name} LB=true bundle exec cap #{stack}_#{env_variant} recovery:delete_old_assets")
    # SKIP_MIGRATE: deploy-time migrations are meaningless before the restore
    # (and fatal on fresh Packer AMIs, whose virgin MySQL has no IRM_<env> yet).
    # recovery:migrate replays real migrations AFTER the restore instead.
    run_cmd("branch=#{branch_name} LB=true SKIP_NOTIFICATION=true SKIP_MIGRATE=true bundle exec cap #{stack}_#{env_variant} IRM:setup")
    run_cmd("branch=#{branch_name} LB=true SKIP_NOTIFICATION=true SKIP_MIGRATE=true bundle exec cap #{stack}_#{env_variant} deploy")
    # Fresh boxes booted BEFORE whenever installed the @reboot crontab, so
    # start the services those entries would have started (xirr_py,
    # prometheus_exporter) — idempotent no-op on already-running boxes
    run_cmd("branch=#{branch_name} LB=true bundle exec cap #{stack}_#{env_variant} IRM:start_boot_services")

    dr_phase "Phase 6/8 · Take traffic offline (nginx maintenance mode)"
    # Now stop sidekiq, puma and monitoring and switch to maintenance mode
    run_cmd("branch=#{branch_name} LB=true bundle exec cap #{stack}_#{env_variant} nginx:switch_maintenance")

    dr_phase "Phase 7/8 · Restore the database from S3 backups"
    # Load the DB from backups (and replay migrations in non-interactive mode)
    restore_tasks.each do |task|
      run_cmd("branch=#{branch_name} bundle exec cap #{stack}_#{env_variant} #{task}")
    end
    backup_bucket = "#{ENV.fetch('AWS_S3_BUCKET', nil)}-backup-xtra"
    record_dr_evidence("Data restored from real backups",
                       "source bucket `#{backup_bucket}` (full + incremental chain; keys named in the transcript)",
                       "`aws s3 ls s3://#{backup_bucket}/` — compare object timestamps against the run window")

    dr_phase "Phase 8/8 · Restore traffic and verify the recovered stack"
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
          Action: ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"],
          Resource: source_buckets.map { |b| "arn:aws:s3:::#{b}/*" } },
        { Effect: "Allow",
          Action: ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"],
          Resource: dest_buckets.map { |b| "arn:aws:s3:::#{b}/*" } }
      ]
    }
    iam.put_role_policy(role_name: role_name, policy_name: "s3-replication", policy_document: permission_policy.to_json)
    iam.get_role(role_name: role_name).role.arn
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

    require "aws-sdk-ssm"
    ENV["PULUMI_CONFIG_PASSPHRASE"] =
      Aws::SSM::Client.new(region: region)
                      .get_parameter(name: "/irm/pulumi/passphrase", with_decryption: true)
                      .parameter.value
    :ssm
  rescue StandardError => e
    raise "PULUMI_CONFIG_PASSPHRASE is not set, is absent from config/credentials/#{env_name}.yml.enc, " \
          "and could not be read from SSM /irm/pulumi/passphrase in #{region}: #{e.message}\n" \
          "   Export it manually:\n" \
          "     export PULUMI_CONFIG_PASSPHRASE=$(aws ssm get-parameter --name /irm/pulumi/passphrase \\\n" \
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

  # Call at the start of any task that shells out to pulumi.
  def ensure_pulumi_backend!(env_name)
    buckets = pulumi_state_buckets(env_name)
    backend = pulumi_current_backend

    if backend.to_s.empty?
      raise "Could not determine the Pulumi backend (`pulumi whoami` failed in ../IRM-Infra). " \
            "Is the Pulumi CLI installed and logged in?"
    end

    unless backend.start_with?("s3://")
      puts "⚠️  Pulumi backend is #{backend} (Pulumi Cloud), not #{env_name}'s state bucket."
      puts "   Fine while #{env_name} is still on Pulumi Cloud. Once migrated, use:"
      puts "     pulumi login \"s3://#{buckets[:primary]}?region=#{buckets[:primary_region]}\""
      return :cloud
    end

    # s3://bucket?region=... — compare the bucket only.
    current_bucket = backend.sub(%r{\As3://}, "").split("?").first
    if current_bucket == buckets[:replica]
      raise "Pulumi is logged into the REPLICA bucket #{current_bucket}. That copy is " \
            "read-only outside a real #{buckets[:primary_region]} outage; writing to it " \
            "creates split-brain state (see IRM-Infra/PULUMI_STATE.md).\n" \
            "   Use: pulumi login \"s3://#{buckets[:primary]}?region=#{buckets[:primary_region]}\""
    end
    if current_bucket != buckets[:primary]
      raise "Pulumi is logged into #{current_bucket}, but #{env_name} state lives in " \
            "#{buckets[:primary]}. Every pulumi read would describe the wrong environment.\n" \
            "   Use: pulumi login \"s3://#{buckets[:primary]}?region=#{buckets[:primary_region]}\""
    end

    case load_pulumi_passphrase!(env_name, buckets[:primary_region])
    when :credentials
      puts "🔑 PULUMI_CONFIG_PASSPHRASE loaded from config/credentials/#{env_name}.yml.enc"
    when :ssm
      puts "🔑 PULUMI_CONFIG_PASSPHRASE loaded from SSM (#{buckets[:primary_region]})"
    end
    puts "✅ Pulumi backend: s3://#{buckets[:primary]} (#{buckets[:primary_region]})"
    :s3
  end

end
