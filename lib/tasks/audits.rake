# Audits table housekeeping. AccountEntry is audited only for hand-made changes on its own screen
# (AccountEntriesController sets manual_change), so the ~500k AccountEntry audits written before that
# (a May 2024 create/destroy burst, then job-written updates) are noise: nothing reads them except the
# generic audit-trail display. (Audits that ARE read as data — approval and KYC-verified times in the
# journey checks, FundFormula migration audits — belong to other models and are never touched here.)
#
#   bundle exec rake audits:purge_account_entry                          # dry run: count and size only
#   EXECUTE=1 EXPORT=/tmp/ae_audits.jsonl.gz bundle exec rake audits:purge_account_entry
#                                                # copy each batch to gzipped JSONL, then delete it
#   bundle exec rake audits:optimize                                     # dry run: table size only
#   EXECUTE=1 bundle exec rake audits:optimize                           # rebuild to give the space back
#
# SAFETY: the audit trail is kept for 7-10 years for fund compliance, so EXECUTE=1 refuses to run without
# EXPORT (a new file: an existing one is never overwritten) — every row is written there before it is
# deleted. Keep that file with the fund records. Deletes only auditable_type = 'AccountEntry'; batches of BATCH (default 5000) ids with a short
# SLEEP (default 0.2s) between them so the replica keeps up. InnoDB keeps the freed space for new rows;
# only audits:optimize (OPTIMIZE TABLE, an online rebuild needing free disk about the table's size)
# returns it to the disk — run it off-hours.
#
# Run per environment on an app box (production.in and production.us are independent).
namespace :audits do
  desc "Report (and with EXECUTE=1 delete) every AccountEntry audit"
  task purge_account_entry: :environment do
    execute = ENV["EXECUTE"] == "1"
    batch_size = (ENV["BATCH"] || 5000).to_i
    pause = (ENV["SLEEP"] || 0.2).to_f
    export_path = ENV.fetch("EXPORT", nil)
    scope = Audit.where(auditable_type: "AccountEntry")

    # What would go: per action, with the date range and the size of the changes column
    scope.group(:action).pluck(:action, Arel.sql("COUNT(*)"), Arel.sql("MIN(created_at)"), Arel.sql("MAX(created_at)"),
                               Arel.sql("SUM(LENGTH(audited_changes))")).each do |action, count, first, last, bytes|
      puts format("%-8s %9d rows  %s .. %s  %6.1f MB", action, count, first&.to_date, last&.to_date, bytes.to_f / 1.megabyte)
    end
    total = scope.count
    puts "#{total} AccountEntry audits#{' (dry run: nothing deleted)' unless execute}"
    next unless execute && total.positive?

    # Compliance keeps the trail for years, so a delete without a copy is refused; so is reusing a
    # file, which a re-run after an interruption would otherwise overwrite with only the rest
    abort "EXPORT=<path.jsonl.gz> is required with EXECUTE=1: every audit is copied there before it is deleted" if export_path.blank?
    abort "#{export_path} already exists: give a new EXPORT path so no earlier copy is overwritten" if File.exist?(export_path)

    gz = Zlib::GzipWriter.open(export_path)
    deleted = 0
    last_id = 0
    begin
      loop do
        # Keyset on id: each batch starts after the last id deleted, so no OFFSET re-scans
        ids = scope.where("id > ?", last_id).order(:id).limit(batch_size).pluck(:id)
        break if ids.empty?

        # The copy is written before the rows go, one JSON object per line
        scope.where(id: ids).order(:id).each { |audit| gz.puts(audit.attributes.to_json) }
        gz.flush
        deleted += Audit.where(id: ids).delete_all
        last_id = ids.last
        puts "  deleted #{deleted}/#{total} (up to id #{last_id})"
        sleep(pause)
      end
    ensure
      gz.close
    end
    puts "Deleted #{deleted} AccountEntry audits (copy in #{export_path}). " \
         "Run audits:optimize to return the space to the disk."
  end

  desc "Report the audits table size (and with EXECUTE=1 rebuild it with OPTIMIZE TABLE)"
  task optimize: :environment do
    execute = ENV["EXECUTE"] == "1"
    conn = ActiveRecord::Base.connection
    unless conn.adapter_name.match?(/mysql|trilogy/i)
      puts "OPTIMIZE TABLE is MySQL-only; #{conn.adapter_name} skipped."
      next
    end

    # Data + index size as InnoDB reports it (an estimate, refreshed by the rebuild)
    size_mb = lambda do
      conn.select_value(<<~SQL.squish).to_f
        SELECT (data_length + index_length + data_free) / 1024 / 1024 FROM information_schema.tables
        WHERE table_schema = DATABASE() AND table_name = 'audits'
      SQL
    end
    before = size_mb.call
    puts format("audits on disk: %.0f MB; the rebuild needs about that much free disk", before)
    unless execute
      puts "(dry run: not rebuilt)"
      next
    end

    # InnoDB maps OPTIMIZE to an online ALTER TABLE ... FORCE: reads and writes continue meanwhile
    conn.select_all("OPTIMIZE TABLE audits").each { |row| puts row.values.join("  ") }
    puts format("audits on disk: %.0f MB before, %.0f MB after", before, size_mb.call)
  end
end
