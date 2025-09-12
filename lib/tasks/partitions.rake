
namespace :partitions do
  desc "Ensure the next calendar year's partition exists for account_entries"
  task ensure_account_entries: :environment do
    conn = ActiveRecord::Base.connection
    current_year = Time.current.year
    required_year = current_year + 1  # e.g. if now is 2025, we only care about 2026

    # Get existing partitions (excluding pmax)
    partitions = conn.select_values(<<~SQL)
      SELECT PARTITION_NAME
      FROM information_schema.PARTITIONS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'account_entries'
        AND PARTITION_NAME NOT IN ('pmax');
    SQL

    years = partitions.map { |p| p.sub(/^p/, "").to_i }.sort
    Rails.logger.info { "Current partitions: #{years.join(', ')} + pmax" }
    Rails.logger.info { "Next calendar year required: #{required_year}" }

    # ✅ Idempotence: if partition already exists, exit
    if years.include?(required_year)
      msg = "✅ Partition for #{required_year} already exists. Nothing to do."
      Rails.logger.info { msg }
      EntityMailer.with(subject: "#{Rails.env}: Partition Check PASSED", msg: { process: "PARTITION CHECK", result: "SKIPPED", message: msg }).notify_info.deliver_now
      next
    end

    # Safety: if pmax already has rows, abort (manual fix needed)
    pmax_rows = conn.select_value("SELECT COUNT(*) FROM account_entries PARTITION (pmax)").to_i
    if pmax_rows > 0
      msg = "❌ ERROR: pmax already has #{pmax_rows} rows. Stop and fix before adding new partitions."
      Rails.logger.error { msg }
      EntityMailer.with(subject: "#{Rails.env}: Partition Check FAILED", msg: { process: "PARTITION CHECK", result: "FAILED", message: msg }).notify_info.deliver_now
      abort(msg)
    end

    # Safety: refuse to skip years (don’t jump from 2025 → 2027)
    if years.max < required_year - 1
      msg = "⚠️ ERROR: Highest partition is #{years.max}, but required is #{required_year}. Add missing years first."
      Rails.logger.error { msg }
      EntityMailer.with(subject: "#{Rails.env}: Partition Check FAILED", msg: { process: "PARTITION CHECK", result: "FAILED", message: msg }).notify_info.deliver_now
      abort(msg)
    end

    # Add the required partition
    Rails.logger.info { "Adding partition for #{required_year}..." }
    conn.execute("ALTER TABLE account_entries DROP PARTITION pmax")
    conn.execute <<~SQL
      ALTER TABLE account_entries
        ADD PARTITION (
          PARTITION p#{required_year} VALUES LESS THAN (#{required_year + 1}),
          PARTITION pmax VALUES LESS THAN MAXVALUE
        );
    SQL
    msg = "✅ Partition p#{required_year} added successfully"
    Rails.logger.info { msg }
    EntityMailer.with(subject: "#{Rails.env}: Partition Check PASSED", msg: { process: "PARTITION CHECK", result: "PASSED", message: msg }).notify_info.deliver_now
  end
end
