# frozen_string_literal: true

# Reconcile an AllocationRun: download BEFORE data, rerun, download AFTER data, compare.
#
# Usage:
#   rails runner scripts/reconcile_allocation_run.rb <allocation_run_id> [--force]
#
#   --force   Skip downloading BEFORE data, force rerun allocation even if
#             after.xlsx exists, then download AFTER and reconcile.
#
# Example:
#   rails runner scripts/reconcile_allocation_run.rb 3005
#   rails runner scripts/reconcile_allocation_run.rb 3005 --force
#
# Output in tmp/reconciliation/<run_id>/:
#   before.xlsx   — AccountEntries before rerun
#   after.xlsx    — AccountEntries after rerun
#   delta.xlsx    — Comparison report

require "fileutils"
require "timeout"

ALLOCATION_TIMEOUT = (ENV["ALLOCATION_TIMEOUT"] || 3600).to_i

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
force = ARGV.delete("--force")
allocation_run_id = ARGV[0].to_i

if allocation_run_id.zero?
  puts "Usage: rails runner scripts/reconcile_allocation_run.rb <allocation_run_id> [--force]"
  exit 1
end

# ---------------------------------------------------------------------------
# Resolve the AllocationRun
# ---------------------------------------------------------------------------
allocation_run = AllocationRun.find_by(id: allocation_run_id)

if allocation_run.nil?
  puts "❌ AllocationRun ##{allocation_run_id} not found"
  exit 1
end

fund   = allocation_run.fund
entity = allocation_run.entity

puts ""
puts "=" * 72
puts " Reconciliation for AllocationRun ##{allocation_run_id}"
puts "   Entity: #{entity.name} (##{entity.id})"
puts "   Fund:   #{fund.name} (##{fund.id})"
puts "   Period: #{allocation_run.start_date} → #{allocation_run.end_date}"
puts "   Status: #{allocation_run.status.inspect}"
puts "   Locked: #{allocation_run.locked}"
puts "=" * 72

# ---------------------------------------------------------------------------
# Output directory
# ---------------------------------------------------------------------------
output_dir = Rails.root.join("tmp", "reconciliation", "run_#{allocation_run_id}")
FileUtils.mkdir_p(output_dir)

puts ""
puts "📁 Output: #{output_dir}"

# ---------------------------------------------------------------------------
# Helper: export AccountEntries to xlsx (skips if file already exists)
# ---------------------------------------------------------------------------
def export_to_xlsx(entries, filepath, label)
  if File.exist?(filepath)
    count = entries.count
    puts "   ⏭️  #{label} already exists, skipping download (#{count} rows)"
    return count
  end

  count = entries.count
  puts "   #{label}: #{count} rows"

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

  puts "   ✅ #{label} → #{filepath}"
  count
end

# ---------------------------------------------------------------------------
# Step 1 — Download BEFORE data
# ---------------------------------------------------------------------------
puts ""
puts "─" * 72
puts " Step 1: Download BEFORE data"
puts "─" * 72

before_file = output_dir.join("before.xlsx")

if force
  unless File.exist?(before_file)
    puts "   ❌ --force mode requires #{before_file} to already exist"
    exit 1
  end
  before_entries = AccountEntry.where(allocation_run_id: allocation_run_id).order(:id)
  before_count   = before_entries.count
  puts "   ⏭️  --force: using existing #{before_file} (#{before_count} rows)"
else
  before_entries = AccountEntry.where(allocation_run_id: allocation_run_id).order(:id)
  before_count   = export_to_xlsx(before_entries, before_file, "BEFORE")
end

after_file = output_dir.join("after.xlsx")

# ---------------------------------------------------------------------------
# Step 2 — Rerun the allocation (skip if after.xlsx already exists, unless --force)
# ---------------------------------------------------------------------------
if File.exist?(after_file) && !force
  puts ""
  puts "─" * 72
  puts " Step 2: Skipped — #{after_file} already exists"
  puts "─" * 72
else
  puts ""
  puts "─" * 72
  puts " Step 2: Rerun allocation (same parameters)"
  puts "─" * 72

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
      result     = :error
      job_error  = e
    end
  end

  # Heartbeat while running
  dots = 0
  while job_thread.alive?
    sleep 5
    dots += 1
    print "\r   Running#{'.' * dots}   "
    $stdout.flush
  end
  job_thread.join
  print "\r" + (" " * 50) + "\r"
  $stdout.flush

  case result
  when :success
    puts "   ✅ Allocation completed"
  when :timeout
    puts "   ⏰ Timed out after #{ALLOCATION_TIMEOUT}s"
    exit 1
  when :error
    puts "   ❌ Failed: #{job_error.class} — #{job_error.message}"
    job_error.backtrace.first(5).each { |l| puts "      #{l}" }
    exit 1
  end

  allocation_run.reload
  puts "   New status: #{allocation_run.status.inspect}"

  unless allocation_run.status == "Success"
    puts "   ❌ Status is not Success — aborting"
    exit 1
  end
end

# ---------------------------------------------------------------------------
# Step 3 — Download AFTER data
# ---------------------------------------------------------------------------
puts ""
puts "─" * 72
puts " Step 3: Download AFTER data"
puts "─" * 72

after_entries = AccountEntry.where(allocation_run_id: allocation_run_id).order(:id)
after_count   = export_to_xlsx(after_entries, after_file, "AFTER")

# ---------------------------------------------------------------------------
# Step 4 — Compare & generate delta xlsx
# ---------------------------------------------------------------------------
puts ""
puts "─" * 72
puts " Step 4: Compare BEFORE vs AFTER → delta.xlsx"
puts "─" * 72

delta_file = output_dir.join("delta.xlsx")

# Build lookup by composite key for matching rows
# Key fields that identify a unique row across runs
key_columns = %w[name capital_commitment_id entry_type reporting_date folio_id cumulative period parent_type parent_id]

def row_key(entry, key_columns)
  key_columns.map { |c| entry.send(c) }
end

# Index before entries by key
before_index = {}
before_entries.find_each do |entry|
  before_index[row_key(entry, key_columns)] = entry
end

# Index after entries by key, detecting added/changed
added   = []  # rows in AFTER but not in BEFORE
changed = []  # rows where key matches but values differ
matched_after_keys = Set.new

after_entries.find_each do |entry|
  key = row_key(entry, key_columns)
  before_entry = before_index[key]

  if before_entry.nil?
    added << entry
  else
    matched_after_keys.add(key)
    # Compare value columns
    val_cols = %w[amount_cents folio_amount_cents tracking_amount_cents explanation notes]
    diffs = {}
    val_cols.each do |col|
      bv = before_entry.send(col)
      av = entry.send(col)
      diffs[col] = { before: bv, after: av } if bv != av
    end
    changed << { key:, before: before_entry, after: entry, diffs: } unless diffs.empty?
  end
end

# Removed = in BEFORE but not matched in AFTER
removed = before_entries.select { |entry| !matched_after_keys.include?(row_key(entry, key_columns)) }

# Sort for consistent output
added.sort_by!   { |e| [e.name, e.capital_commitment_id, e.reporting_date] }
removed.sort_by! { |e| [e.name, e.capital_commitment_id, e.reporting_date] }
numeric_val_cols = %w[amount_cents folio_amount_cents tracking_amount_cents]
changed.sort_by! { |c| -numeric_val_cols.sum { |col| c[:diffs][col] ? (c[:diffs][col][:after].to_f - c[:diffs][col][:before].to_f).abs : 0 } }

# --- Build delta xlsx ---
all_columns = AccountEntry.column_names

Axlsx::Package.new do |p|
  # Sheet 1: Summary
  p.workbook.add_worksheet(name: "Summary") do |sheet|
    sheet.add_row ["Reconciliation Report — AllocationRun ##{allocation_run_id}"]
    sheet.add_row ["Entity", entity.name, "ID", entity.id]
    sheet.add_row ["Fund", fund.name, "ID", fund.id]
    sheet.add_row ["Period", allocation_run.start_date.to_s, "→", allocation_run.end_date.to_s]
    sheet.add_row []
    sheet.add_row ["Metric", "Before", "After", "Diff"]
    sheet.add_row ["Row Count", before_count, after_count, after_count - before_count]

    %w[amount_cents folio_amount_cents tracking_amount_cents].each do |col|
      b = before_entries.sum(col) || 0
      a = after_entries.sum(col)  || 0
      sheet.add_row [col, b, a, a - b]
    end

    sheet.add_row []
    sheet.add_row ["Delta Breakdown", "Count"]
    sheet.add_row ["Added rows", added.count]
    sheet.add_row ["Removed rows", removed.count]
    sheet.add_row ["Changed rows (values differ)", changed.count]
    sheet.add_row ["Unchanged rows", matched_after_keys.size - changed.count]
  end

  # Sheet 2: Added
  p.workbook.add_worksheet(name: "Added") do |sheet|
    sheet.add_row all_columns
    added.each { |e| sheet.add_row all_columns.map { |c| e.send(c) } }
  end

  # Sheet 3: Removed
  p.workbook.add_worksheet(name: "Removed") do |sheet|
    sheet.add_row all_columns
    removed.each { |e| sheet.add_row all_columns.map { |c| e.send(c) } }
  end

  # Sheet 4: Changed (side-by-side: key cols + value before/after/diff)
  p.workbook.add_worksheet(name: "Changed") do |sheet|
    header = key_columns + %w[field before after diff]
    sheet.add_row header
    changed.each do |c|
      c[:diffs].each do |field, vals|
        diff = if vals[:before].is_a?(Numeric) && vals[:after].is_a?(Numeric)
                 vals[:after] - vals[:before]
               else
                 "N/A"
               end
        row_data = c[:key] + [field, vals[:before], vals[:after], diff]
        sheet.add_row row_data
      end
    end
  end

  p.serialize(delta_file.to_s)
end

puts "   ✅ Delta → #{delta_file}"
puts "      Added: #{added.count}, Removed: #{removed.count}, Changed: #{changed.count}, Unchanged: #{matched_after_keys.size - changed.count}"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
puts ""
puts "─" * 72
puts " Done"
puts "─" * 72
puts "   #{before_file}"
puts "   #{after_file}"
puts "   #{delta_file}"
puts ""
