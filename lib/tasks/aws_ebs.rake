# lib/tasks/aws_ebs.rake
#
# EBS encryption rollout + snapshot/AMI retention hygiene, for both AWS accounts.
#
#   bundle exec rake "aws:ebs_status[staging.in]"                   # read-only audit
#   bundle exec rake "aws:ebs_default_encryption[staging.in]"       # DRY RUN (default)
#   EXECUTE=1 bundle exec rake "aws:ebs_default_encryption[production.us]"
#   bundle exec rake "aws:ebs_cleanup[staging.in]"                  # DRY RUN
#   EXECUTE=1 bundle exec rake "aws:ebs_cleanup[staging.in]"        # keep 3 AMIs/name, sweep orphans >7d
#   EXECUTE=1 KEEP=0 DAYS=0 REGIONS=us-east-1 bundle exec rake "aws:ebs_cleanup[staging.in]"
#                                                                   # decommission sweep (staging.us is dead)
#   bundle exec rake "aws:ebs_encrypt_plan[production.in]"          # read-only: which machines would restart?
#   EXECUTE=1 bundle exec rake "aws:ebs_encrypt_instance[AppServer,staging.in]"  # STOPS the instance!
#   bundle exec rake "aws:ebs_delete_replaced[staging.in]"          # DRY RUN
#   EXECUTE=1 bundle exec rake "aws:ebs_delete_replaced[staging.in]"
#                                                                   # delete swap leftovers once replacements verified
#
# WHY THIS EXISTS
#   Audit 2026-09-01: production.in (ap-south-1) is fully encrypted behind a
#   customer-managed KMS key with encryption-by-default ON — but nowhere else is.
#   staging and production.us run entirely unencrypted volumes/snapshots/AMIs,
#   and DR-region copies inherit that. Separately, the weekly AMI bake
#   (aws:create_and_copy_ami → cleanup_amis in aws_utils.rb) deregisters old
#   AMIs but never deletes their backing snapshots, which is how hundreds of
#   orphaned EBS snapshots piled up (155 in staging ap-south-2 alone). This file
#   adds the missing retention sweep and the encryption path.
#
# ENCRYPTION STRATEGY (no prod disruption)
#   1. aws:ebs_default_encryption — account+region setting; affects only NEWLY
#      created volumes and snapshot/AMI *copies*. Zero impact on anything
#      running. Once on, the weekly bake's cross-region CopyImage lands
#      encrypted automatically, and any instance (re)launched by pulumi/DR
#      comes up with encrypted volumes even from an unencrypted AMI.
#   2. Existing volumes cannot be encrypted in place — flipping one requires
#      stop → snapshot → encrypted copy → new volume → swap → start. That is
#      aws:ebs_encrypt_instance, which refuses to touch production unless
#      ALLOW_STOP=1 is set (run it in a maintenance window, one instance at a
#      time). Do NOT run it casually against production.
#   3. Old unencrypted snapshots age out through aws:ebs_cleanup once the
#      volumes they came from are encrypted and new bakes replace old AMIs.
#
# SAFETY
#   - Dry run by default; every mutating call goes through .act, so without
#     EXECUTE=1 nothing can be modified.
#   - STS account id must match the env (staging 174852986003, production
#     825199636520 — separate accounts; wrong keys exported = hard abort).
#   - Cleanup never deletes a snapshot referenced by a still-registered AMI,
#     and skips anything tagged Retain=true.
#   - Volumes are never deleted by cleanup — the encrypt swap leaves the old
#     unencrypted volume detached and tagged DeleteAfterVerify=true.
#     aws:ebs_delete_replaced deletes those leftovers, but only after checking
#     the source instance is running again with every attached volume encrypted.

require_relative "aws_utils" # AMI_KEEP_DEFAULT — shared with the bake's cleanup_amis

module AwsEbs
  module_function

  # env_name => the AWS account that env's resources live in. staging.us is
  # deliberately absent: that environment is decommissioned — its us-east-1
  # leftovers are cleaned via REGIONS=us-east-1 under staging.in creds.
  ENV_ACCOUNTS = {
    "staging.in" => "174852986003",
    "production.in" => "825199636520",
    "production.us" => "825199636520"
  }.freeze

  def execute? = ENV["EXECUTE"].present?

  # Strict integer parsing: 0 is the documented delete-EVERYTHING sentinel for
  # both knobs, so a typo (KEEP=all) or an empty value (KEEP=) must abort, not
  # silently to_i into the most destructive mode.
  def int_env(key, default)
    raw = ENV.fetch(key, nil)
    return default if raw.nil?

    Integer(raw)
  rescue ArgumentError
    abort "❌ #{key} must be an integer, got #{raw.inspect}"
  end

  # How many AMIs to keep per Name tag — the same constant cleanup_amis uses,
  # so the 02:00 bake and this 04:00 sweep can never disagree on retention.
  def keep = int_env("KEEP", AwsUtils::AMI_KEEP_DEFAULT)

  # Orphaned snapshots younger than this many days are left alone — protects a
  # snapshot that is mid-bake (created but not yet referenced by an AMI).
  def orphan_days = int_env("DAYS", 7)

  # Every mutating call funnels through here so DRY RUN can't possibly mutate.
  def act(description)
    if execute?
      yield
      puts "  ✅ #{description}"
    else
      puts "  [dry-run] would #{description}"
    end
  rescue Aws::EC2::Errors::ServiceError => e
    # Keep sweeping — one stuck resource must not abort a retention run.
    puts "  ❌ failed to #{description}: #{e.message}"
  end

  def guard!(env_name, account)
    if env_name.present?
      expected = ENV_ACCOUNTS[env_name]
      abort "❌ unknown env '#{env_name}' — expected one of #{ENV_ACCOUNTS.keys.join(', ')}" if expected.nil?
      return if expected == account

      abort "❌ #{env_name} lives in account #{expected} but these credentials are account #{account} — " \
            "export the right env's AWS keys before re-running"
    else
      # Scheduled (cron) invocation on a server: no env arg, the box's own
      # credentials apply. The box does know which environment it is
      # (Rails.env is staging or production — config/environments has both),
      # so cross-check account against THAT rather than accepting either known
      # account: credentials copied from the wrong account would otherwise run
      # a weekly EXECUTE=1 deletion sweep against the wrong environment.
      expected = Rails.env.staging? ? "174852986003" : "825199636520"
      return if expected == account

      abort "❌ this box is Rails.env=#{Rails.env} (account #{expected}) but the credentials are " \
            "account #{account} — refusing to sweep the wrong account"
    end
  end

  # Primary region plus the DR/backup region for this env — the bake copies
  # AMIs there, so retention has to sweep both. REGIONS narrows the blast radius.
  def regions
    return ENV["REGIONS"].split(",").map(&:strip) if ENV["REGIONS"].present?

    [ENV.fetch("AWS_REGION", nil), ENV.fetch("AWS_BACKUP_REGION", nil), ENV.fetch("AWS_S3_REPLICA_REGION", nil)].compact_blank.uniq
  end

  def ec2(region) = Aws::EC2::Client.new(region: region)

  def name_of(taggable)
    Array(taggable.tags).find { |t| t.key == "Name" }&.value
  end

  def retain?(taggable)
    Array(taggable.tags).any? { |t| t.key == "Retain" && t.value == "true" }
  end

  def delete_after_verify?(taggable)
    Array(taggable.tags).any? { |t| t.key == "DeleteAfterVerify" && t.value == "true" }
  end

  # ---------------------------------------------------------------------------
  # Status (read-only)
  # ---------------------------------------------------------------------------
  def status_region(region)
    client = ec2(region)
    default_on = client.get_ebs_encryption_by_default.ebs_encryption_by_default
    # flat_map over the pageable responses — .volumes/.snapshots on the bare
    # response reads only the FIRST page (max 1000), and the snapshot pile-up
    # this file exists to fix can exceed that.
    vols  = client.describe_volumes.flat_map(&:volumes)
    snaps = client.describe_snapshots(owner_ids: ["self"]).flat_map(&:snapshots)
    amis  = client.describe_images(owners: ["self"]).flat_map(&:images)
    plain_amis = amis.count { |i| i.block_device_mappings.any? { |m| m.ebs && !m.ebs.encrypted } }

    puts "  encryption-by-default: #{default_on ? '✅ ON' : '❌ OFF'}"
    puts "  volumes:   #{vols.count { |v| !v.encrypted }} unencrypted / #{vols.size} total"
    puts "  snapshots: #{snaps.count { |s| !s.encrypted }} unencrypted / #{snaps.size} total " \
         "(#{snaps.sum(&:volume_size)} GiB)"
    puts "  AMIs:      #{plain_amis} with unencrypted mappings / #{amis.size} total"
  end

  # ---------------------------------------------------------------------------
  # Encryption by default (account+region setting, non-disruptive)
  # ---------------------------------------------------------------------------
  def enable_default_region(region)
    client = ec2(region)
    current_key = client.get_ebs_default_kms_key_id.kms_key_id
    if client.get_ebs_encryption_by_default.ebs_encryption_by_default
      puts "  already ON (default key: #{current_key})"
    else
      act "enable EBS encryption-by-default in #{region}" do
        client.enable_ebs_encryption_by_default
      end
    end
    # Optional customer-managed key (production.in uses one); default aws/ebs
    # key otherwise — fine for same-account use, but note a CMK is required if
    # snapshots ever need sharing across accounts. Checked OUTSIDE the
    # already-ON branch: a key change must apply even when encryption-by-default
    # was enabled long ago.
    if ENV["KMS_KEY_ID"].present? && ENV["KMS_KEY_ID"] != current_key
      act "set default EBS KMS key in #{region} to #{ENV.fetch('KMS_KEY_ID', nil)} (was #{current_key})" do
        client.modify_ebs_default_kms_key_id(kms_key_id: ENV.fetch("KMS_KEY_ID", nil))
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Retention cleanup: old AMIs + their snapshots + orphaned snapshots
  # ---------------------------------------------------------------------------
  def cleanup_region(region)
    client = ec2(region)
    # Pageable response: enumerate every page, not just the first.
    images = client.describe_images(owners: ["self"]).flat_map(&:images)

    # Group AMIs the same way cleanup_amis does — by Name tag (both the bake and
    # the cross-region copy tag Name). AMIs without a Name tag fall back to
    # their AMI name stripped of timestamp/copy noise so old hand-made images
    # still group ("DB_Redis_ES-20250817..." → "DB_Redis_ES").
    grouped = images.group_by do |img|
      name_of(img) || img.name.to_s.delete_prefix('Copy-').sub(/[-_]?20\d{6}.*\z/, "").strip
    end

    doomed_snapshot_ids = []
    grouped.sort.each do |label, imgs|
      # AMIs whose whole name was a timestamp reduce to "" — unrelated one-off
      # images would share a single keep-N budget and expire each other. Leave
      # them alone entirely (except under an explicit KEEP=0 decommission).
      if label.empty? && !keep.zero?
        puts "  AMI group '': #{imgs.size} unrelated unnamed image(s) — skipped (tag them to manage retention)"
        next
      end

      sorted = imgs.sort_by(&:creation_date)
      if keep.zero?
        doomed = sorted # KEEP=0 → decommission: delete every AMI regardless of state
      else
        # Only completed images take part in the keep window. The 02:00 bake's
        # cross-region copy is still "pending" when this runs at 04:00 — it
        # must not occupy a survivor slot (evicting the oldest GOOD AMI), nor
        # be deregistered mid-copy. Failed images don't count as survivors
        # either, so a streak of failed copies can't age out the last good AMIs.
        available = sorted.select { |i| i.state == "available" }
        doomed = available[0...-keep] || []
      end
      survivors = sorted - doomed
      puts "  AMI group '#{label}': #{sorted.size} total, keeping #{survivors.size}, expiring #{doomed.size}"

      doomed.each do |img|
        if retain?(img)
          puts "    ⏭  #{img.image_id} tagged Retain=true — skipped"
          next
        end
        snap_ids = img.block_device_mappings.filter_map { |m| m.ebs&.snapshot_id }
        act "deregister #{img.image_id} (#{img.name}, #{img.creation_date})" do
          client.deregister_image(image_id: img.image_id)
        end
        # The snapshots behind a deregistered AMI serve nothing — deleting them
        # here is the fix for the historical pile-up (cleanup_amis left them).
        snap_ids.each do |sid|
          doomed_snapshot_ids << sid
          act "delete backing snapshot #{sid}" do
            client.delete_snapshot(snapshot_id: sid)
          end
        end
      end
    end

    # Orphan sweep: self-owned snapshots referenced by NO currently registered
    # AMI. "Referenced" is computed from the full pre-cleanup image list, so a
    # snapshot only counts as an orphan if it was already dangling before this
    # run (this pass mops up years of cleanup_amis leftovers; snapshots expired
    # above were deleted with their AMI already).
    referenced = images.flat_map { |i| i.block_device_mappings.filter_map { |m| m.ebs&.snapshot_id } }.to_set
    cutoff = Time.zone.now - (orphan_days * 86_400)
    orphans = client.describe_snapshots(owner_ids: ["self"]).flat_map(&:snapshots).reject do |s|
      referenced.include?(s.snapshot_id) ||
        doomed_snapshot_ids.include?(s.snapshot_id) || # already handled above
        s.start_time > cutoff ||                       # too fresh — may be mid-bake
        retain?(s) ||
        # Pre-encryption recovery snapshots are ebs_delete_replaced's to remove
        # (alongside their old volume, after the replacement is verified) — the
        # unattended weekly cron must not eat someone's rollback path first.
        delete_after_verify?(s)
    end

    puts "  orphaned snapshots older than #{orphan_days}d: #{orphans.size} (#{orphans.sum(&:volume_size)} GiB)"
    orphans.sort_by(&:start_time).each do |s|
      act "delete orphan #{s.snapshot_id} (#{s.volume_size} GiB, #{s.start_time.strftime('%Y-%m-%d')}, #{name_of(s) || s.description[0, 60]})" do
        client.delete_snapshot(snapshot_id: s.snapshot_id)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Encryption plan (read-only): which instances would the rollout restart?
  # ---------------------------------------------------------------------------
  # Lists every instance carrying at least one unencrypted volume — i.e. every
  # machine aws:ebs_encrypt_instance would have to stop/swap/start. Use this to
  # size the production maintenance window before touching anything.
  def encrypt_plan_region(region, env_name)
    client = ec2(region)
    instances = client.describe_instances(filters: [
                                            { name: "instance-state-name", values: %w[running stopped] }
                                          ]).flat_map(&:reservations).flat_map(&:instances)

    # One bulk describe_volumes instead of one call per instance.
    vol_ids = instances.flat_map { |i| i.block_device_mappings.map { |m| m.ebs.volume_id } }
    vols_by_id = vol_ids.empty? ? {} : client.describe_volumes(volume_ids: vol_ids).flat_map(&:volumes).index_by(&:volume_id)

    needing = instances.filter_map do |inst|
      plain = inst.block_device_mappings.filter_map { |m| vols_by_id[m.ebs.volume_id] }.reject(&:encrypted)
      [inst, plain] if plain.any?
    end

    if needing.empty?
      puts "  ✅ no instances with unencrypted volumes — nothing to restart"
      return
    end

    # Instances sharing a Name tag (e.g. two AppServers behind an ALB) need the
    # INSTANCE_ID env var — ebs_encrypt_instance refuses ambiguous names.
    name_counts = needing.map { |inst, _| name_of(inst).to_s }.tally

    needing.sort_by { |inst, _| name_of(inst).to_s }.each do |inst, plain|
      # A running instance takes downtime (stop → swap → start); a stopped one
      # can be encrypted without any restart at all.
      impact = inst.state.name == "running" ? "⚠️  RESTART REQUIRED (currently running)" : "no restart (already stopped)"
      puts "  #{name_of(inst) || '<unnamed>'} (#{inst.instance_id}, #{inst.instance_type}) — #{impact}"
      plain.each { |v| puts "      #{v.volume_id}: #{v.size} GiB #{v.volume_type} unencrypted" }
      if name_of(inst).blank?
        # encrypt_instance targets by tag:Name — an unnamed instance can't be
        # addressed at all until someone tags it.
        puts "      → no Name tag: add one before it can be encrypted with aws:ebs_encrypt_instance"
      else
        id_hint = " INSTANCE_ID=#{inst.instance_id}" if name_counts[name_of(inst).to_s] > 1
        puts "      → EXECUTE=1#{' ALLOW_STOP=1' if env_name.to_s.start_with?('production')}#{id_hint} " \
             "bundle exec rake \"aws:ebs_encrypt_instance[#{name_of(inst)},#{env_name}]\""
      end
    end
    puts "  total: #{needing.size} instance(s), #{needing.count { |i, _| i.state.name == 'running' }} of them need a restart"
  end

  # ---------------------------------------------------------------------------
  # Encrypt one instance's volumes via stop → snapshot → encrypted copy → swap
  # ---------------------------------------------------------------------------
  def encrypt_instance(instance_name, env_name)
    region = ENV.fetch("AWS_REGION", nil)
    client = ec2(region)

    # Stopping an instance is downtime — production requires an explicit second
    # key so this can only happen deliberately, in a maintenance window.
    abort "❌ refusing to stop a production instance — re-run with ALLOW_STOP=1 inside a maintenance window" if env_name.to_s.start_with?("production") && ENV["ALLOW_STOP"].blank?

    instances = client.describe_instances(filters: [
                                            { name: "tag:Name", values: [instance_name] },
                                            { name: "instance-state-name", values: %w[running stopped] }
                                          ]).flat_map(&:reservations).flat_map(&:instances)
    abort "❌ no instance named '#{instance_name}' in #{region}" if instances.empty?
    abort "❌ #{instances.size} instances named '#{instance_name}' — disambiguate with INSTANCE_ID" if instances.size > 1 && ENV["INSTANCE_ID"].blank?

    instance = ENV["INSTANCE_ID"].present? ? instances.find { |i| i.instance_id == ENV["INSTANCE_ID"] } : instances.first
    abort "❌ INSTANCE_ID #{ENV.fetch('INSTANCE_ID', nil)} not found among '#{instance_name}' instances" unless instance

    vol_ids = instance.block_device_mappings.map { |m| m.ebs.volume_id }
    vols = client.describe_volumes(volume_ids: vol_ids).volumes
    targets = vols.reject(&:encrypted)
    if targets.empty?
      puts "  ✅ every volume on #{instance.instance_id} is already encrypted — nothing to do"
      return
    end

    # Map volume → its attachment metadata now; needed to reattach identically.
    plan = targets.map do |v|
      att = instance.block_device_mappings.find { |m| m.ebs.volume_id == v.volume_id }
      { volume: v, device: att.device_name, delete_on_termination: att.ebs.delete_on_termination }
    end

    puts "  instance #{instance.instance_id} (#{instance_name}), state #{instance.state.name}"
    plan.each do |p|
      puts "  will encrypt #{p[:volume].volume_id} (#{p[:volume].size} GiB #{p[:volume].volume_type} at #{p[:device]})"
    end
    unless execute?
      puts "  [dry-run] would stop the instance, snapshot each volume, copy the snapshots encrypted" \
           "#{" with key #{ENV['KMS_KEY_ID']}" if ENV['KMS_KEY_ID'].present?}, build replacement volumes, swap, restart"
      return
    end

    was_running = instance.state.name == "running"
    # Stop FIRST, then snapshot: a snapshot taken while the instance writes
    # would silently lose everything written between snapshot and swap.
    if was_running
      puts "  ⏸  stopping #{instance.instance_id}..."
      client.stop_instances(instance_ids: [instance.instance_id])
      client.wait_until(:instance_stopped, instance_ids: [instance.instance_id]) do |w|
        w.max_attempts = 40
        w.delay = 15
      end
    end

    plan.each do |p|
      old = p[:volume]
      # DeleteAfterVerify on the recovery snapshot keeps it out of the weekly
      # orphan sweep — ebs_delete_replaced removes it together with the old
      # volume once the replacement is verified.
      snap = client.create_snapshot(volume_id: old.volume_id,
                                    description: "pre-encryption #{instance_name} #{old.volume_id}",
                                    tag_specifications: [{ resource_type: "snapshot",
                                                           tags: [{ key: "Name", value: "pre-encryption-#{instance_name}" },
                                                                  { key: "DeleteAfterVerify", value: "true" }] }]).snapshot_id
      puts "  📸 #{snap} from #{old.volume_id} — waiting..."
      # 480 × 30s = 4h: a large volume's first snapshot / encrypted copy can
      # take well over the default hour, and giving up here strands a stopped
      # instance — waiting longer is strictly better than aborting.
      client.wait_until(:snapshot_completed, snapshot_ids: [snap]) do |w|
        w.max_attempts = 480
        w.delay = 30
      end

      copy_params = { source_region: region, source_snapshot_id: snap, encrypted: true,
                      description: "encrypted #{instance_name} #{old.volume_id}" }
      copy_params[:kms_key_id] = ENV["KMS_KEY_ID"] if ENV["KMS_KEY_ID"].present?
      enc_snap = client.copy_snapshot(copy_params).snapshot_id
      puts "  🔐 encrypted copy #{enc_snap} — waiting..."
      client.wait_until(:snapshot_completed, snapshot_ids: [enc_snap]) do |w|
        w.max_attempts = 480
        w.delay = 30
      end

      # Replacement volume mirrors the old one's performance characteristics.
      create_params = { availability_zone: old.availability_zone, snapshot_id: enc_snap,
                        volume_type: old.volume_type,
                        tag_specifications: [{ resource_type: "volume",
                                               tags: old.tags.presence || [{ key: "Name", value: instance_name }] }] }
      create_params[:iops]       = old.iops       if %w[io1 io2 gp3].include?(old.volume_type) && old.iops
      create_params[:throughput] = old.throughput if old.volume_type == "gp3" && old.throughput
      new_vol = client.create_volume(create_params).volume_id
      client.wait_until(:volume_available, volume_ids: [new_vol]) do |w|
        w.max_attempts = 40
        w.delay = 15
      end

      puts "  🔁 swapping #{old.volume_id} → #{new_vol} at #{p[:device]}"
      client.detach_volume(volume_id: old.volume_id)
      client.wait_until(:volume_available, volume_ids: [old.volume_id]) do |w|
        w.max_attempts = 40
        w.delay = 15
      end
      client.attach_volume(volume_id: new_vol, instance_id: instance.instance_id, device: p[:device])
      client.wait_until(:volume_in_use, volume_ids: [new_vol]) do |w|
        w.max_attempts = 40
        w.delay = 15
      end
      # Reapply delete-on-termination (attach_volume always defaults it false).
      client.modify_instance_attribute(instance_id: instance.instance_id,
                                       block_device_mappings: [{ device_name: p[:device],
                                                                 ebs: { volume_id: new_vol,
                                                                        delete_on_termination: p[:delete_on_termination] } }])
      # Old volume stays detached, clearly labelled — deleted MANUALLY once the
      # instance is verified healthy on the new one. The interim snapshots age
      # out via the orphan sweep.
      client.create_tags(resources: [old.volume_id],
                         tags: [{ key: "Name", value: "pre-encryption-#{instance_name}" },
                                { key: "DeleteAfterVerify", value: "true" }])
      puts "  ✅ #{new_vol} attached; old #{old.volume_id} detached and tagged pre-encryption-#{instance_name}"
    end

    if was_running
      puts "  ▶️  starting #{instance.instance_id}..."
      client.start_instances(instance_ids: [instance.instance_id])
      client.wait_until(:instance_running, instance_ids: [instance.instance_id]) do |w|
        w.max_attempts = 40
        w.delay = 15
      end
    end
    puts "  ✅ done — verify the app, then run aws:ebs_delete_replaced to remove the volumes tagged DeleteAfterVerify"
  rescue StandardError => e
    # A dry run mutates nothing — a read failure there needs no runbook.
    raise unless execute?

    # A failed AWS call or timed-out waiter lands here mid-run. Nothing is
    # rolled back automatically — rolling forward/back blind (e.g. restarting
    # an instance whose root volume is detached) could make things worse, so
    # spell out the state for the operator instead of dying with a bare trace.
    puts "\n❌ #{e.class}: #{e.message}"
    # defined?/&. because an error can fire before `instance` is assigned.
    puts "❌ swap INTERRUPTED — #{defined?(instance) && instance ? instance.instance_id : instance_name} is likely still STOPPED, and a volume may be " \
         "mid-swap (detached old / unattached new). Before restarting, check in the EC2 console that " \
         "every device on the instance has a volume attached; the pre-encryption snapshots still exist " \
         "for recovery. Fix attachments, start the instance manually, then re-run this task (it skips " \
         "already-encrypted volumes)."
    raise
  end

  # ---------------------------------------------------------------------------
  # Delete swapped-out unencrypted volumes once their replacement is verified
  # ---------------------------------------------------------------------------
  # Cleans up what encrypt_instance deliberately leaves behind. A volume is
  # only eligible if ALL of these hold:
  #   - tagged DeleteAfterVerify=true (only the swap writes that tag)
  #   - unencrypted and detached ("available") — an attached or encrypted
  #     volume is never a swap leftover
  #   - the instance it came from (Name tag "pre-encryption-<InstanceName>") is
  #     running again with every attached volume encrypted — the "confirmed
  #     functional" gate the operator would otherwise check by hand
  def delete_replaced_region(region)
    client = ec2(region)
    vols = client.describe_volumes(filters: [{ name: "tag:DeleteAfterVerify", values: ["true"] }]).flat_map(&:volumes)
    if vols.empty?
      puts "  no volumes tagged DeleteAfterVerify=true — nothing to delete"
      return
    end

    vols.each do |v|
      label = "#{v.volume_id} (#{v.size} GiB, #{name_of(v)})"
      instance_name = name_of(v).to_s.delete_prefix("pre-encryption-")

      if v.state != "available"
        puts "  ⏭  #{label} is #{v.state}, not detached — skipped"
        next
      end
      if v.encrypted
        # Belt and braces: nothing should ever tag an encrypted volume, but if
        # something did we refuse rather than delete a possibly-live copy.
        puts "  ⏭  #{label} is encrypted — not a swap leftover, skipped"
        next
      end
      if retain?(v)
        puts "  ⏭  #{label} tagged Retain=true — skipped"
        next
      end
      if instance_name.blank?
        puts "  ⏭  #{label} has no pre-encryption-<name> tag — can't verify its replacement, skipped"
        next
      end
      unless replacement_healthy?(client, instance_name)
        puts "  ⏭  #{label}: '#{instance_name}' is not running with all volumes encrypted in #{region} — " \
             "verify the instance and re-run (for an instance that stays stopped, e.g. DbCheckInstance, " \
             "set ALLOW_STOPPED=1 to accept a stopped-but-encrypted replacement)"
        next
      end

      act "delete #{label} — replacement on '#{instance_name}' verified encrypted + running" do
        client.delete_volume(volume_id: v.volume_id)
      end

      # The recovery snapshot taken from this volume (tagged DeleteAfterVerify
      # by encrypt_instance, and skipped by the weekly orphan sweep for exactly
      # this moment) goes with it — the verified replacement makes it obsolete.
      client.describe_snapshots(owner_ids: ["self"],
                                filters: [{ name: "volume-id", values: [v.volume_id] },
                                          { name: "tag:DeleteAfterVerify", values: ["true"] }])
            .flat_map(&:snapshots).each do |s|
        act "delete recovery snapshot #{s.snapshot_id} (from #{v.volume_id})" do
          client.delete_snapshot(snapshot_id: s.snapshot_id)
        end
      end
    end
  end

  # True only when at least one instance with this Name is running AND every
  # volume attached to every such instance is encrypted. With several instances
  # sharing a Name (the two prod.us AppServers) this deliberately requires ALL
  # of them encrypted before ANY leftover is deleted — conservative on purpose.
  # ALLOW_STOPPED=1 also accepts stopped instances: needed for boxes that are
  # normally kept stopped (DbCheckInstance) and so can never be seen "running";
  # the operator asserts functionality instead of this check.
  def replacement_healthy?(client, instance_name)
    states = ENV["ALLOW_STOPPED"].present? ? %w[running stopped] : ["running"]
    instances = client.describe_instances(filters: [
                                            { name: "tag:Name", values: [instance_name] },
                                            { name: "instance-state-name", values: states }
                                          ]).flat_map(&:reservations).flat_map(&:instances)
    return false if instances.empty?

    vol_ids = instances.flat_map { |i| i.block_device_mappings.map { |m| m.ebs.volume_id } }
    return false if vol_ids.empty?

    client.describe_volumes(volume_ids: vol_ids).volumes.all?(&:encrypted)
  end
end

namespace :aws do
  # rubocop:disable Rails/RakeEnvironment -- as in aws:tls_policy: a bare
  # :environment prerequisite resolves to aws:environment inside this namespace.

  # Shared preamble: env selection, account guard, mode banner.
  def ebs_task_setup(task_name, args)
    Rake::Task["environment"].invoke
    Rake::Task["aws:environment"].reenable
    Rake::Task["aws:environment"].invoke(args[:env_name])

    ident = Aws::STS::Client.new(region: "us-east-1").get_caller_identity
    AwsEbs.guard!(args[:env_name], ident.account)

    mode = AwsEbs.execute? ? "EXECUTE" : "DRY RUN"
    puts "== #{task_name} [#{args[:env_name] || 'server env'}] account #{ident.account} — #{mode} =="
  end

  desc "EBS encryption status per region (read-only; ENV: REGIONS)"
  task :ebs_status, [:env_name] do |_t, args|
    ebs_task_setup("aws:ebs_status", args)
    AwsEbs.regions.each do |region|
      puts "\n-- #{region} --"
      AwsEbs.status_region(region)
    end
  end

  desc "Enable EBS encryption-by-default per region (ENV: EXECUTE, REGIONS, KMS_KEY_ID)"
  task :ebs_default_encryption, [:env_name] do |_t, args|
    ebs_task_setup("aws:ebs_default_encryption", args)
    AwsEbs.regions.each do |region|
      puts "\n-- #{region} --"
      AwsEbs.enable_default_region(region)
    end
    puts(AwsEbs.execute? ? "\n== done ==" : "\n== dry run complete — re-run with EXECUTE=1 to apply ==")
  end

  desc "Expire old AMIs incl. their snapshots + delete orphaned snapshots (ENV: EXECUTE, KEEP, DAYS, REGIONS)"
  task :ebs_cleanup, [:env_name] do |_t, args|
    ebs_task_setup("aws:ebs_cleanup", args)
    puts "   keeping #{AwsEbs.keep} AMIs per name; orphan snapshots must be >#{AwsEbs.orphan_days}d old"
    AwsEbs.regions.each do |region|
      puts "\n-- #{region} --"
      AwsEbs.cleanup_region(region)
    end
    puts(AwsEbs.execute? ? "\n== done ==" : "\n== dry run complete — re-run with EXECUTE=1 to apply ==")
  end

  desc "List instances that the encryption rollout would restart (read-only; ENV: REGIONS)"
  task :ebs_encrypt_plan, [:env_name] do |_t, args|
    ebs_task_setup("aws:ebs_encrypt_plan", args)
    AwsEbs.regions.each do |region|
      puts "\n-- #{region} --"
      AwsEbs.encrypt_plan_region(region, args[:env_name])
    end
  end

  desc "Delete swapped-out unencrypted volumes once replacements are verified (ENV: EXECUTE, REGIONS, ALLOW_STOPPED)"
  task :ebs_delete_replaced, [:env_name] do |_t, args|
    ebs_task_setup("aws:ebs_delete_replaced", args)
    AwsEbs.regions.each do |region|
      puts "\n-- #{region} --"
      AwsEbs.delete_replaced_region(region)
    end
    puts(AwsEbs.execute? ? "\n== done ==" : "\n== dry run complete — re-run with EXECUTE=1 to apply ==")
  end

  desc "Encrypt an instance's EBS volumes via stop/swap/start (ENV: EXECUTE, ALLOW_STOP, KMS_KEY_ID, INSTANCE_ID)"
  task :ebs_encrypt_instance, [:instance_name, :env_name] do |_t, args|
    ebs_task_setup("aws:ebs_encrypt_instance", args)
    abort "❌ instance name required, e.g. rake \"aws:ebs_encrypt_instance[AppServer,staging.in]\"" if args[:instance_name].blank?
    AwsEbs.encrypt_instance(args[:instance_name], args[:env_name])
  end
  # rubocop:enable Rails/RakeEnvironment
end
