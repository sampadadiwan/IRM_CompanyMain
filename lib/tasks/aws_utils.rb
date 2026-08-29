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
    puts "Running command: #{command}"
    opts = cwd ? { chdir: cwd } : {}
    Open3.popen3(command, opts) do |stdin, stdout, stderr, wait_thr|
        # Handle stdout
        while line = stdout.gets
          puts line
        end

        # Optionally, you can handle errors by reading from stderr:
        while err_line = stderr.gets

          puts "🚨 Error: #{err_line}"
        end

        # Wait for the command to complete and fetch the exit status
        exit_status = wait_thr.value
        unless exit_status.success?

          raise "Command failed with status (#{exit_status.exitstatus})"
        end
    end
  end

  def cleanup_amis(name_tag, region, number_to_keep=3)
    name_tag = name_tag.strip

    puts "🧹 Cleaning up old AMIs with name: #{name_tag} in region: #{region}"
    Aws.config.update({ region: })

    ec2 = Aws::EC2::Client.new

    all_amis = ec2.describe_images({ owners: ['self'] }).images
    all_amis.each do |ami|
      tag_value = ami.tags.find { |t| t.key == 'Name' }&.value

      puts "🔍 AMI: #{ami.image_id}, Name Tag: '#{tag_value}'"  # Show exact tag value
    end

    name_tag = name_tag.strip

    amis = all_amis.select do |ami|
      tag_value = ami.tags.find { |t| t.key == 'Name' }&.value
      tag_value&.strip == name_tag
    end.sort_by { |ami| ami.creation_date }



    puts "ℹ️ Found #{amis.length} AMIs with name: #{name_tag}. Retaining #{number_to_keep} AMIs"

    # Retain the last number_to_keep AMIs, delete the rest
    if amis.length > number_to_keep

      puts "🗑️ Deleting #{amis.length - number_to_keep} old AMIs"
      amis_to_delete = amis[0...(amis.length - number_to_keep)]
    else

      puts "👍 No old AMIs to delete"
      amis_to_delete = []  # Nothing to delete if there are fewer than or exactly 7 AMIs
    end

    amis_to_delete.each do |ami|
      begin

        ec2.deregister_image(image_id: ami.image_id)
        puts "✅ Deregistered old AMI: #{ami.image_id} with name: #{ami.name}"
      rescue Aws::EC2::Errors::ServiceError => e
        puts "❌ Failed to deregister AMI: #{ami.image_id}. Error: #{e.message}"
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
    def initialize(*targets)
      @targets = targets
    end

    def write(*args)
      @targets.each do |t|
        t.write(*args)
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
  def write_dr_report(stack:, region:, env_variant:, branch:, result:, started_at:, drill: false)
    finished = Time.now
    rebuild_secs = (finished - started_at).round
    dir = Rails.root.join("docs", "dr_runs")
    FileUtils.mkdir_p(dir)
    path = dir.join("#{branch}.md")

    phase_rows = DR_PHASES.map { |t, s, e| "| #{t} | #{hms(((e || finished) - s).round)} |" }.join("\n")
    evidence_rows = DR_EVIDENCE.map { |claim, (ev, how)| "| #{claim} | #{ev} | #{how} |" }.join("\n")

    File.write(path, <<~MD)
      # Disaster Recovery #{drill ? 'Drill' : 'Run'} Report

      | | |
      |---|---|
      | **Result** | **#{result}** |
      | Stack | #{stack} (#{env_variant}) |
      | Target region | #{region} |
      | Branch deployed | `#{branch}` |
      | Started | #{started_at.utc.iso8601} |
      | Finished | #{finished.utc.iso8601} |
      | Measured rebuild time | **#{hms(rebuild_secs)}** (#{(rebuild_secs / 60.0).round(1)} min) |
      | Executed by | #{ENV['USER'] || 'unknown'}@#{`hostname`.strip} |
      #{drill ? "\n> This was a **drill** against `#{stack}`, not a response to a real incident.\n" : ''}
      ## What the measured time does and does not cover

      The figure above is **rebuild time**, not end-to-end RTO. It is measured
      from the start of the recovery command to the point where the stack passed
      verification.

      **Included:** Pulumi provisioning, config rewrite, application deploy to
      both app servers, database restore from S3 (primary + replica in
      parallel), replication reset, migration replay, and the full
      `recovery:verify` health scorecard.

      **Excluded:** incident detection, the human decision to declare a disaster
      (DR_GUIDE §4), and DNS cutover plus TTL propagation — `aws:dns_cutover` is
      manual by design and is never invoked by the recovery sequence (DR_GUIDE
      §8). A true incident-to-service-restored RTO is this figure **plus** those
      three components.

      ## Phase timings

      | Phase | Duration |
      |---|---|
      #{phase_rows}

      ## Independently verifiable evidence

      Each row names a record held outside this repository. Nothing here relies
      on trusting this file.

      | Claim | Evidence | How to verify independently |
      |---|---|---|
      #{evidence_rows}

      ## Verification result

      The recovery sequence fails loudly unless `cap #{stack}_#{env_variant} recovery:verify`
      passes on every app server — it checks nginx, puma, sidekiq registration,
      HTTP through the full serving chain to MySQL / Redis / Elasticsearch / S3,
      migration currency, restored-data freshness, DB-box daemons, backup cron
      arming, and a live replication round-trip. The per-check scorecard is in
      the run transcript.

      Re-run at any time against a still-running stack:

      ```bash
      LB=true bundle exec cap #{stack}_#{env_variant} recovery:verify
      ```

      ## Full transcript

      The complete console output of this run — every command, its output, and
      the verification scorecard — was captured automatically to
      `docs/dr_runs/#{branch}.log`. Read it alongside this report: the report
      says what is claimed and how to check it independently, the transcript
      says what actually happened, line by line.

      ---
      Generated #{finished.utc.iso8601} by `#{drill ? 'rake aws:dr_drill' : 'rake aws:setup_infra'}`.
    MD

    puts "🧾 Evidence report written to #{path.to_s.sub(Rails.root.to_s + '/', '')}"
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

    # 8.4: SHOW MASTER STATUS -> SHOW BINARY LOG STATUS
    result = source_client.query('SHOW BINARY LOG STATUS')
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
    puts "Setting up replication on the destination with query: #{change_source_query.squish}"
    destination_client.query(change_source_query)

    puts 'Starting replica'
    destination_client.query('START REPLICA')

    status = destination_client.query('SHOW REPLICA STATUS')
    puts status.first.inspect
  end

end