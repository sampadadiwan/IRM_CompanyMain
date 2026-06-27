# frozen_string_literal: true

# Reconcile one or more AllocationRuns: download BEFORE data, rerun, download AFTER data, compare.
#
# Usage:
#   rails runner scripts/reconcile_allocation_run.rb <id1> [<id2> ...] [--force]
#
# Multiple IDs run in parallel threads; a summary table is printed at the end.
#
#   --force   Skip downloading BEFORE data, force rerun allocation even if
#             after.xlsx exists, then download AFTER and reconcile.
#
# Example:
#   rails runner scripts/reconcile_allocation_run.rb 3005
#   rails runner scripts/reconcile_allocation_run.rb 3005 3006 3007
#   rails runner scripts/reconcile_allocation_run.rb 3005 3006 --force
#
# Output in tmp/reconciliation/<run_id>/:
#   before.xlsx   — AccountEntries before rerun
#   after.xlsx    — AccountEntries after rerun
#   delta.xlsx    — Comparison report
#
# ── Architecture ──────────────────────────────────────────────────────────────
#
# The allocation engine deletes old generated entries and inserts new ones during
# a rerun.  This means the live database is fundamentally different before vs.
# after the rerun.  To get a correct diff we MUST snapshot the data at two points
# in time and compare the snapshots — NOT re-query the live DB after the rerun.
#
#   Step 1   Export BEFORE snapshot to before.xlsx  (before rerun)
#   Step 2   Rerun allocation (mutates the DB)
#   Step 3   Export AFTER  snapshot to after.xlsx   (after  rerun)
#   Step 4   Load BOTH xlsx files into memory and compare
#
# ── Why not query the DB in Step 4? ──────────────────────────────────────────
#
# ActiveRecord relations are lazy.  If we wrote:
#
#   before_entries = AccountEntry.where(...)   # lazy, no query yet
#   export_to_xlsx(before_entries, ...)        # executes query, writes xlsx
#   # ... rerun happens here, DB is mutated ...
#   before_entries.find_each { ... }           # RE-QUERIES — gets AFTER data!
#
# The second iteration would return the post-rerun data, making the "before"
# comparison meaningless.  Rails' query cache *might* save us in some
# configurations, but it is not guaranteed (the rerun job may use a different
# connection, clear the cache, etc.).  The only reliable approach is to read
# the xlsx files that were written at the correct point in time.
#
# ── Multiple entries with the same key ───────────────────────────────────────
#
# Some fund formulas use rule_type "AllocateAccountEntryIndividual-*" which
# sets `grouped: false`.  When multiple fund-level entries exist with the same
# name/entry_type, each one is allocated individually, producing multiple
# folio-level entries with the identical composite key
# (name + capital_commitment_id + entry_type + …).
#
# The old code stored only ONE entry per key in a plain Hash, so the second
# entry silently overwrote the first.  When the single "before" entry was then
# compared against the first "after" entry, it produced a false positive diff.
#
# The fix: store an ARRAY of entries per key and match them in FIFO order
# (both snapshots are ordered by id ASC, so the Nth before entry corresponds
# to the Nth after entry for the same key).

require "fileutils"
require "timeout"
require "roo"

ALLOCATION_TIMEOUT = (ENV["ALLOCATION_TIMEOUT"] || 3600).to_i

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
force = ARGV.delete("--force")
allocation_run_ids = ARGV.map(&:to_i).reject(&:zero?)

if allocation_run_ids.empty?
  puts "Usage: rails runner scripts/reconcile_allocation_run.rb <id1> [<id2> ...] [--force]"
  exit 1
end

# ---------------------------------------------------------------------------
# Thread-safe logging
# Each line is prefixed with [#run_id] so parallel output stays readable.
# ---------------------------------------------------------------------------
OUTPUT_MUTEX = Mutex.new

def tlog(run_id, msg)
  OUTPUT_MUTEX.synchronize { puts "[##{run_id}] #{msg}" }
end

# ---------------------------------------------------------------------------
# Helper: export AccountEntries to xlsx (skips if file already exists)
# `logger` is a callable used for all output so it works inside threads.
# ---------------------------------------------------------------------------
# NOTE: This function writes the xlsx but also returns the row count.  The
# `entries` relation IS executed here (via .count and .find_each), so the
# xlsx is a correct point-in-time snapshot.  After this function returns,
# the `entries` relation should NOT be re-used — it would re-query the DB.
def export_to_xlsx(entries, filepath, label, overwrite: false, logger: method(:puts))
  # `overwrite: true` forces a fresh export even if the file exists.  This is
  # essential for the AFTER snapshot in --force mode: --force reruns the
  # allocation (mutating the DB), so a stale after.xlsx from a PREVIOUS run no
  # longer matches the data.  Without this, --force would rerun the allocation
  # but silently keep the old snapshot, and the delta would compare against
  # data that the rerun already replaced.
  if File.exist?(filepath) && !overwrite
    count = entries.count
    logger.call("   ⏭️  #{label} already exists, skipping download (#{count} rows)")
    return count
  end

  count = entries.count
  logger.call("   #{label}: #{count} rows")

  columns = AccountEntry.column_names

  Axlsx::Package.new do |p|
    p.workbook.add_worksheet(name: "AccountEntries") do |sheet|
      sheet.add_row columns
      entries.find_each do |entry|
        sheet.add_row columns.map { |col| entry.send(col) }
      end
    end
    p.serialize(filepath.to_s)
  end

  logger.call("   ✅ #{label} → #{filepath}")
  count
end

# ---------------------------------------------------------------------------
# Helper: load entries from an xlsx snapshot into an array of hashes.
# Each hash is keyed by column name (string) with the raw cell value.
#
# We use `each_row_streaming` to avoid loading the entire sheet into memory
# at once (important for large allocation runs with 10K+ entries).
# ---------------------------------------------------------------------------
def load_entries_from_xlsx(filepath)
  xlsx = Roo::Spreadsheet.open(filepath.to_s)
  sheet = xlsx.sheet("AccountEntries")

  header = nil
  entries = []

  sheet.each_row_streaming do |row|
    vals = row.map(&:value)
    if header.nil?
      # First row is the column header
      header = vals
    else
      entry = {}
      header.each_with_index { |col, idx| entry[col] = vals[idx] }
      entries << entry
    end
  end

  entries
end

# ---------------------------------------------------------------------------
# Reconcile a single AllocationRun.
# Raises on unrecoverable errors so the caller (thread or main) can catch them.
# Returns :skipped when there is nothing to do, :success on completion.
# ---------------------------------------------------------------------------
def reconcile_one(allocation_run_id, force:)
  # Convenience: every log line is prefixed with [#run_id]
  log = ->(msg) { tlog(allocation_run_id, msg) }

  # ── Resolve the AllocationRun ──────────────────────────────────────────────
  allocation_run = AllocationRun.find_by(id: allocation_run_id)
  raise "AllocationRun ##{allocation_run_id} not found" if allocation_run.nil?

  fund   = allocation_run.fund
  entity = allocation_run.entity

  Chewy.strategy(:atomic) { EntitySetting.disable_all }

  log.call("")
  log.call("=" * 60)
  log.call(" Reconciliation for AllocationRun ##{allocation_run_id}")
  log.call("   Entity: #{entity.name} (##{entity.id})")
  log.call("   Fund:   #{fund.name} (##{fund.id})")
  log.call("   Period: #{allocation_run.start_date} → #{allocation_run.end_date}")
  log.call("   Status: #{allocation_run.status.inspect}")
  log.call("   Locked: #{allocation_run.locked}")
  log.call("=" * 60)

  # ── Guard: nothing to reconcile if the run has no AccountEntries ───────────
  if AccountEntry.where(allocation_run_id: allocation_run_id).count.zero?
    log.call("")
    log.call("⚠️  AllocationRun ##{allocation_run_id} has no AccountEntries — nothing to reconcile.")
    return :skipped
  end

  # ── Output directory ───────────────────────────────────────────────────────
  output_dir = Rails.root.join("tmp", "reconciliation", "run_#{allocation_run_id}")
  FileUtils.mkdir_p(output_dir)
  log.call("")
  log.call("📁 Output: #{output_dir}")

  before_file = output_dir.join("before.xlsx")
  after_file  = output_dir.join("after.xlsx")

  # ── Step 1: Download BEFORE data ──────────────────────────────────────────
  # CRITICAL: This MUST happen BEFORE the rerun (Step 2).  The xlsx file is our
  # point-in-time snapshot of the database state before any mutations.
  log.call("")
  log.call("─" * 60)
  log.call(" Step 1: Download BEFORE data")
  log.call("─" * 60)

  before_entries = AccountEntry
    .where(allocation_run_id: allocation_run_id)
    .order(:capital_commitment_id, :entity_id, :fund_id, :investor_id, :folio_id, :reporting_date, :entry_type, :name, :id)

  if force
    # --force mode: skip the BEFORE export, use the existing before.xlsx.
    # This is useful when you already have a before.xlsx from a previous run
    # and just want to re-rerun and compare.
    raise "--force mode requires #{before_file} to already exist" unless File.exist?(before_file)
    log.call("   ⏭️  --force: using existing #{before_file} (#{before_entries.count} rows)")
  else
    # Normal path: query the DB and write the snapshot.
    # `before_entries` is a lazy ActiveRecord relation.  It gets executed inside
    # export_to_xlsx (via .count and .find_each).  After export_to_xlsx returns,
    # DO NOT re-query this relation — the rerun will have mutated the data.
    export_to_xlsx(before_entries, before_file, "BEFORE", logger: log)
  end

  # ── Step 2: Rerun the allocation ───────────────────────────────────────────
  # The allocation engine DELETES old generated entries and INSERTs new ones.
  # After this step, the database state is fundamentally different from Step 1.
  if File.exist?(after_file) && !force
    log.call("")
    log.call("─" * 60)
    log.call(" Step 2: Skipped — #{after_file} already exists")
    log.call("─" * 60)
  else
    log.call("")
    log.call("─" * 60)
    log.call(" Step 2: Rerun allocation (same parameters)")
    log.call("─" * 60)

    # Mark as Pending so the engine knows to run
    allocation_run.update_column(:status, "Pending")

    result    = nil
    job_error = nil

    job_thread = Thread.new do
      begin
        Timeout.timeout(ALLOCATION_TIMEOUT) do
          AccountEntryAllocationJob.perform_now(
            fund.id,
            allocation_run.start_date,
            allocation_run.end_date,
            user_id:           allocation_run.user_id,
            run_allocations:   allocation_run.run_allocations,
            explain:           true,
            generate_soa:      false,
            statement_for:     allocation_run.statement_for,
            template_id:       allocation_run.template_name,
            fund_ratios:       allocation_run.fund_ratios,
            rule_for:          allocation_run.rule_for,
            tag_list:          allocation_run.tag_list,
            allocation_run_id: allocation_run.id,
          )
        end
        result = :success
      rescue Timeout::Error
        result = :timeout
      rescue => e
        result    = :error
        job_error = e
      end
    end

    # Heartbeat — periodic log line so it remains readable when multiple
    # runs print in parallel (the \r trick doesn't work across threads).
    elapsed = 0
    while job_thread.alive?
      sleep 30
      elapsed += 30
      log.call("   Still running… #{elapsed}s elapsed") if job_thread.alive?
    end
    job_thread.join

    case result
    when :success
      log.call("   ✅ Allocation completed")
    when :timeout
      raise "⏰ Timed out after #{ALLOCATION_TIMEOUT}s"
    when :error
      log.call("   ❌ Failed: #{job_error.class} — #{job_error.message}")
      job_error.backtrace.first(5).each { |l| log.call("      #{l}") }
      raise "Allocation job failed"
    end

    allocation_run.reload
    log.call("   New status: #{allocation_run.status.inspect}")
    raise "Status is not Success after rerun — aborting" unless allocation_run.status == "Success"
  end

  # ── Step 3: Download AFTER data ───────────────────────────────────────────
  # This happens AFTER the rerun, so the xlsx captures the post-mutation state.
  log.call("")
  log.call("─" * 60)
  log.call(" Step 3: Download AFTER data")
  log.call("─" * 60)

  after_entries = AccountEntry
    .where(allocation_run_id: allocation_run_id)
    .order(:capital_commitment_id, :entity_id, :fund_id, :investor_id, :folio_id, :reporting_date, :entry_type, :name, :id)
  # In --force mode the allocation was just rerun, so the AFTER snapshot MUST be
  # regenerated (overwrite: force) — otherwise we'd compare against a stale file
  # from a previous run and never actually see the effect of the rerun.
  export_to_xlsx(after_entries, after_file, "AFTER", overwrite: force, logger: log)

  # ── Step 4: Compare BEFORE vs AFTER → delta.xlsx ─────────────────────────
  # IMPORTANT: We read from the xlsx FILES, not from the database.
  #
  # Why?  The `before_entries` and `after_entries` relations above were used
  # ONLY to write the xlsx snapshots.  Re-querying them now would hit the live
  # database, which has been mutated by the rerun.  The xlsx files are the
  # ONLY correct source of before/after data.
  #
  # We use Roo to parse the xlsx files into arrays of plain hashes.  This also
  # avoids loading ActiveRecord objects (which carry dirty tracking, type
  # casting, etc.) — hashes are lighter and faster for comparison.
  log.call("")
  log.call("─" * 60)
  log.call(" Step 4: Compare BEFORE vs AFTER → delta.xlsx")
  log.call("─" * 60)

  delta_file = output_dir.join("delta.xlsx")

  # Load snapshots from xlsx files.
  # These are plain hashes — no ActiveRecord overhead, no accidental DB queries.
  before_rows = load_entries_from_xlsx(before_file)
  after_rows  = load_entries_from_xlsx(after_file)

  before_count = before_rows.size
  after_count  = after_rows.size

  # ── Composite key definition ───────────────────────────────────────────────
  # These columns uniquely identify a "slot" that an entry fills.  For most
  # formulas (grouped: true), there is exactly one entry per key.  For
  # AllocateAccountEntryIndividual-* formulas (grouped: false), there can be
  # multiple entries with the same key (one per fund-level source entry).
  key_columns = %w[name capital_commitment_id entry_type reporting_date folio_id cumulative period parent_type parent_id]

  # ── Index before entries ───────────────────────────────────────────────────
  # We store an ARRAY per key (not a single entry) because AllocateAccountEntry-
  # Individual-* formulas can produce multiple entries with the same key.
  #
  # Each entry gets a unique `_idx` (its position in the original array) so we
  # can track which specific entries have been matched.  We use `_idx` rather
  # than `id` because:
  #   1. We're working with plain hashes, not AR objects — no `.id` method.
  #   2. The xlsx rows don't have a reliable unique identifier (the `id` column
  #      differs between before/after runs since entries are re-inserted).
  #   3. Array index is stable within a single load and guarantees FIFO order.
  before_index = Hash.new { |h, k| h[k] = [] }
  before_rows.each_with_index do |entry, idx|
    # Tag the original hash in-place so the same hash object in before_rows
    # carries the index and can be checked later in the "removed" calculation.
    # Using entry.merge(...) would return a NEW hash — the original would stay
    # untagged and every entry would appear "removed".
    entry["_idx"] = idx
    before_index[key_columns.map { |c| entry[c] }] << entry
  end

  # ── Compare after entries against before index ─────────────────────────────
  # For each after entry, we find the FIRST unmatched before entry with the same
  # key (FIFO order).  Within a key, both snapshots are ordered by id ASC (the
  # query's final tie-breaker), i.e. creation order — which is deterministic across
  # runs for a given set of formulas.  So the Nth before entry corresponds to the
  # Nth after entry for the same key.  (We deliberately tie-break on :id, NOT on
  # :amount_cents: amount_cents is one of the values that legitimately changes
  # between runs, so ordering by it could swap the pairing of same-key entries and
  # manufacture false "changed" diffs.)
  #
  # Three outcomes:
  #   1. No matching before entry → the after entry is "added"
  #   2. Matching before entry found, values differ → "changed"
  #   3. Matching before entry found, values identical → "unchanged" (not stored)
  added   = []  # rows in AFTER but not in BEFORE
  changed = []  # rows where key matches but values differ
  matched_before_indices = Set.new  # tracks which before rows (by _idx) were matched

  after_rows.each do |entry|
    key = key_columns.map { |c| entry[c] }
    before_entries_for_key = before_index[key]

    # FIFO: find the first before entry with this key that hasn't been matched yet
    before_entry = before_entries_for_key.find { |be| !matched_before_indices.include?(be["_idx"]) }

    if before_entry.nil?
      # No unmatched before entry exists → this after entry is brand new
      added << entry
    else
      matched_before_indices << before_entry["_idx"]

      # ── Numeric value columns ──────────────────────────────────────────────
      # These are the columns we actually care about reconciling.  Compare with
      # `.to_f` so that nil vs 0.0 and Integer vs Float (artifacts of the
      # xlsx → Roo round-trip) are NOT reported as spurious diffs.
      #
      # NOTE: tracking_amount_cents is INTENTIONALLY excluded.  It is populated
      # from the fund's tracking-currency exchange rate, which changes over time —
      # the BEFORE snapshot carries tracking computed at whatever rate (or legacy
      # value) existed when the run was originally created, while the AFTER rerun
      # uses the current rate.  Comparing it therefore produces large, meaningless
      # diffs that drown out the real allocation differences.  We reconcile only
      # the rate-independent outputs (amount_cents, folio_amount_cents).
      numeric_cols = %w[amount_cents folio_amount_cents]
      diffs = {}
      numeric_cols.each do |col|
        diffs[col] = { before: before_entry[col], after: entry[col] } if before_entry[col].to_f != entry[col].to_f
      end

      # ── Context columns (explanation, notes) ──────────────────────────────
      # The explanation embeds the computed result and object inspections, so it
      # almost always differs WHENEVER a numeric value differs — and can also drift
      # for benign reasons (object inspect strings) while the numbers are identical.
      # We therefore DO NOT let explanation/notes mark a row as "changed" on their
      # own; we only attach them once a numeric column already moved, so they
      # explain WHY the numbers changed without inflating the changed-row count
      # with value-identical rows.
      unless diffs.empty?
        %w[explanation notes].each do |col|
          diffs[col] = { before: before_entry[col], after: entry[col] } if before_entry[col] != entry[col]
        end
        changed << { key:, before: before_entry, after: entry, diffs: }
      end
    end
  end

  # ── Removed entries ────────────────────────────────────────────────────────
  # Any before entry that was never matched by an after entry is "removed".
  # This happens when the new code no longer generates an entry that the old
  # code did (e.g., a formula was removed or an entry was filtered out).
  removed = before_rows.select { |entry| !matched_before_indices.include?(entry["_idx"]) }

  # ── Sort for consistent output ─────────────────────────────────────────────
  # Use .to_s on all fields to handle nil values safely (Ruby's <=> raises
  # "comparison of Array with Array failed" when comparing nil to an integer).
  added.sort_by!   { |e| [e["name"].to_s, e["capital_commitment_id"].to_s, e["reporting_date"].to_s] }
  removed.sort_by! { |e| [e["name"].to_s, e["capital_commitment_id"].to_s, e["reporting_date"].to_s] }

  # Sort changed entries by total absolute change (largest diffs first).
  # tracking_amount_cents is excluded here too — see the comparison block above.
  numeric_val_cols = %w[amount_cents folio_amount_cents]
  changed.sort_by! { |c| -numeric_val_cols.sum { |col| c[:diffs][col] ? (c[:diffs][col][:after].to_f - c[:diffs][col][:before].to_f).abs : 0 } }

  # ── Build delta xlsx ───────────────────────────────────────────────────────
  # Four sheets:
  #   Summary   — High-level metrics (row counts, totals, delta breakdown)
  #   Added     — Full rows that exist in AFTER but not in BEFORE
  #   Removed   — Full rows that exist in BEFORE but not in AFTER
  #   Changed   — Side-by-side comparison of value columns that differ
  all_columns = AccountEntry.column_names

  Axlsx::Package.new do |p|
    # ── Sheet 1: Summary ─────────────────────────────────────────────────────
    p.workbook.add_worksheet(name: "Summary") do |sheet|
      sheet.add_row ["Reconciliation Report — AllocationRun ##{allocation_run_id}"]
      sheet.add_row ["Entity", entity.name, "ID", entity.id]
      sheet.add_row ["Fund", fund.name, "ID", fund.id]
      sheet.add_row ["Period", allocation_run.start_date.to_s, "→", allocation_run.end_date.to_s]
      sheet.add_row []
      sheet.add_row ["Metric", "Before", "After", "Diff"]
      sheet.add_row ["Row Count", before_count, after_count, after_count - before_count]

      # Column totals — computed from the in-memory xlsx data, NOT from the DB.
      # amount_cents / folio_amount_cents are the reconciled outputs.
      %w[amount_cents folio_amount_cents].each do |col|
        b = before_rows.sum { |r| r[col].to_f }
        a = after_rows.sum  { |r| r[col].to_f }
        sheet.add_row [col, b, a, a - b]
      end

      # tracking_amount_cents is shown for information only and is NOT part of the
      # reconciliation: it depends on the tracking-currency exchange rate, which
      # differs between the original run (BEFORE) and the rerun (AFTER), so any
      # diff here is expected and not a code difference.
      b_track = before_rows.sum { |r| r["tracking_amount_cents"].to_f }
      a_track = after_rows.sum  { |r| r["tracking_amount_cents"].to_f }
      sheet.add_row ["tracking_amount_cents (informational — not reconciled)", b_track, a_track, a_track - b_track]

      sheet.add_row []
      sheet.add_row ["Delta Breakdown", "Count"]
      sheet.add_row ["Added rows", added.count]
      sheet.add_row ["Removed rows", removed.count]
      sheet.add_row ["Changed rows (values differ)", changed.count]
      # Unchanged = total after entries that matched (after_count - added) minus those that differed
      sheet.add_row ["Unchanged rows", (after_count - added.count) - changed.count]
    end

    # ── Sheet 2: Added ───────────────────────────────────────────────────────
    # Full rows that exist in AFTER but have no matching counterpart in BEFORE.
    # These are entries the new code generates that the old code did not.
    p.workbook.add_worksheet(name: "Added") do |sheet|
      sheet.add_row all_columns
      added.each { |e| sheet.add_row all_columns.map { |c| e[c] } }
    end

    # ── Sheet 3: Removed ─────────────────────────────────────────────────────
    # Full rows that exist in BEFORE but have no matching counterpart in AFTER.
    # These are entries the old code generated that the new code no longer does.
    p.workbook.add_worksheet(name: "Removed") do |sheet|
      sheet.add_row all_columns
      removed.each { |e| sheet.add_row all_columns.map { |c| e[c] } }
    end

    # ── Sheet 4: Changed ─────────────────────────────────────────────────────
    # Side-by-side comparison: for each pair of (before, after) entries that
    # share the same key but have different values, we show one row per field
    # that differs, with the before/after ids, before value, after value, and
    # numeric diff.  The ids come from the xlsx snapshot and let you trace back
    # to the actual database records for troubleshooting.
    p.workbook.add_worksheet(name: "Changed") do |sheet|
      header = key_columns + %w[before_id after_id field before after diff]
      sheet.add_row header
      changed.each do |c|
        c[:diffs].each do |field, vals|
          diff = if vals[:before].is_a?(Numeric) && vals[:after].is_a?(Numeric)
                   vals[:after] - vals[:before]
                 else
                   "N/A"
                 end
          row_data = c[:key] + [c[:before]["id"], c[:after]["id"], field, vals[:before], vals[:after], diff]
          sheet.add_row row_data
        end
      end
    end

    p.serialize(delta_file.to_s)
  end

  log.call("   ✅ Delta → #{delta_file}")
  log.call("      Added: #{added.count}, Removed: #{removed.count}, Changed: #{changed.count}, Unchanged: #{(after_count - added.count) - changed.count}")

  log.call("")
  log.call("─" * 60)
  log.call(" Done")
  log.call("─" * 60)
  log.call("   #{before_file}")
  log.call("   #{after_file}")
  log.call("   #{delta_file}")
  log.call("")

  :success
end

# ---------------------------------------------------------------------------
# Dispatch — single run goes direct; multiple IDs run in parallel threads.
# ---------------------------------------------------------------------------
if allocation_run_ids.size == 1
  begin
    result = reconcile_one(allocation_run_ids.first, force: force)
    exit result == :skipped ? 0 : 0
  rescue => e
    puts "❌ #{e.message}"
    exit 1
  end
else
  puts "Starting #{allocation_run_ids.size} reconciliation(s) in parallel…"

  results       = {}
  results_mutex = Mutex.new

  threads = allocation_run_ids.map do |id|
    Thread.new do
      outcome = begin
        reconcile_one(id, force: force)
      rescue => e
        { error: e.message }
      end
      results_mutex.synchronize { results[id] = outcome }
    end
  end

  threads.each(&:join)

  # ── Summary ────────────────────────────────────────────────────────────────
  puts ""
  puts "=" * 72
  puts " Summary (#{allocation_run_ids.size} runs)"
  puts "=" * 72
  allocation_run_ids.each do |id|
    case results[id]
    when :success then puts "  ✅ ##{id} — success"
    when :skipped then puts "  ⚠️  ##{id} — skipped (no AccountEntries)"
    else               puts "  ❌ ##{id} — #{results[id][:error]}"
    end
  end
  puts ""

  failed_count = results.values.count { |r| r.is_a?(Hash) && r[:error] }
  exit failed_count > 0 ? 1 : 0
end
