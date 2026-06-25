# frozen_string_literal: true

# Download AccountEntries as CSV for the latest successful AllocationRun
# of each fund belonging to the specified entities.
#
# Usage:
#   rails runner scripts/download_account_entries.rb <entity_id_1> [entity_id_2 ...]
#
# Example:
#   rails runner scripts/download_account_entries.rb 1 2 3
#
# Output:
#   One CSV per fund written to tmp/exports/{entity_name}_{fund_name}_account_entries_{date}.csv

require "csv"
require "fileutils"

entity_ids = ARGV.map(&:to_i)

if entity_ids.empty?
  puts "Usage: rails runner scripts/download_account_entries.rb <entity_id_1> [entity_id_2 ...]"
  exit 1
end

output_dir = Rails.root.join("tmp", "exports")
FileUtils.mkdir_p(output_dir)

total_files = 0
date_stamp = Time.zone.now.strftime("%Y-%m-%d")

entity_ids.each do |entity_id|
  entity = Entity.find_by(id: entity_id)

  if entity.nil?
    puts "⚠️  Entity #{entity_id} not found, skipping"
    next
  end

  puts "Processing entity #{entity_id} (#{entity.short_name || entity.name})..."

  funds = entity.funds.to_a

  if funds.empty?
    puts "  ⚠️  No funds found for entity #{entity_id}, skipping"
    next
  end

  funds.each do |fund|
    latest_run = AllocationRun.where(fund_id: fund.id, status: "Success")
                               .order(created_at: :desc)
                               .first

    if latest_run.nil?
      puts "  Fund: #{fund.name} → no successful AllocationRun found, skipping"
      next
    end

    entries = AccountEntry.where(allocation_run_id: latest_run.id)
                          .order(:id)

    # Sanitize names for filesystem safety
    safe_entity_name = entity.short_name.to_s.gsub(/[^a-zA-Z0-9_-]/, "_").gsub(/_+/, "_").gsub(/^_|_$/, "")
    safe_fund_name   = fund.name.to_s.gsub(/[^a-zA-Z0-9_-]/, "_").gsub(/_+/, "_").gsub(/^_|_$/, "")

    filename = "#{safe_entity_name}_#{safe_fund_name}_account_entries_#{date_stamp}.csv"
    filepath = output_dir.join(filename)

    columns = AccountEntry.column_names

    CSV.open(filepath, "wb") do |csv|
      csv << columns
      entries.find_each do |entry|
        csv << columns.map { |col| entry.send(col) }
      end
    end

    row_count = entries.count
    puts "  Fund: #{fund.name} → latest successful run: #{latest_run.end_date} (id=#{latest_run.id})"
    puts "    → Writing #{filename} (#{row_count} rows)"
    total_files += 1
  end
end

puts
puts "Done. #{total_files} file(s) written to #{output_dir}"
