# Incremental since_inception allocation: move funds onto it, back off it, and correct stored totals.
# See docs/modules/allocation/incremental_allocation_history.md section 12 and AccountEntryAllocation::IncrementalMigration.
#
# Thin wrappers: the plans, their printout and the writes all live in IncrementalMigration, which the fund
# formulas page (Actions > Incremental allocation) uses too. Prefer the page for a single fund.
#
#   # One fund, or every fund in an entity. Dry run by default: prints the formula edits, blockers,
#   # and the corrected starting values, and changes nothing. APPLY=true does it.
#   bundle exec rake "allocation:enable_incremental[fund,319]"
#   bundle exec rake "allocation:enable_incremental[entity,6349]" APPLY=true
#
#   # Every formula enable_incremental edits also gets a description of what it computes and why it was
#   # changed (written whole if blank, appended otherwise). Backfill funds migrated before that:
#   bundle exec rake "allocation:describe_incremental[fund,342]" APPLY=true
#
#   # Back off: flag off, formulas and their descriptions restored from the audit trail (tracking fixes kept)
#   bundle exec rake "allocation:disable_incremental[fund,319]" APPLY=true
#
#   # Correct one formula's stored since-inception entries on a date (DRY_RUN=true to preview)
#   bundle exec rake "allocation:reseed_carry_forward[319,2026-07-31,230 231 232 233 234 235]"
namespace :allocation do
  def incremental_funds(scope, id)
    case scope
    when "fund" then Fund.where(id: Integer(id))
    when "entity" then Fund.where(entity_id: Integer(id)).where(id: FundFormula.select(:fund_id)).order(:id)
    else abort "scope must be 'fund' or 'entity', e.g. allocation:enable_incremental[entity,6349]"
    end
  end

  desc "Move a fund, or every fund in an entity, onto incremental allocation (APPLY=true to write)"
  task :enable_incremental, %i[scope id] => :environment do |_t, args|
    apply = ENV["APPLY"] == "true"
    puts apply ? "APPLYING" : "DRY RUN (APPLY=true to write)"
    results = incremental_funds(args[:scope], args[:id]).map do |fund|
      puts
      [fund, AccountEntryAllocation::IncrementalMigration.new(fund).enable!(apply:)]
    rescue StandardError => e
      # One fund failing (e.g. a formula that no longer validates) rolls back that fund only
      puts "[fund #{fund.id}] FAILED, nothing changed for this fund: #{e.class}: #{e.message}"
      [fund, :failed]
    end

    puts "\nSummary"
    results.each { |fund, result| puts format("  %-6<id>s %-50<name>s %<result>s", id: fund.id, name: fund.name.truncate(50), result:) }
  end

  desc "Describe the formulas enable_incremental edited, where the description is missing (APPLY=true to write)"
  task :describe_incremental, %i[scope id] => :environment do |_t, args|
    apply = ENV["APPLY"] == "true"
    puts apply ? "APPLYING" : "DRY RUN (APPLY=true to write)"
    incremental_funds(args[:scope], args[:id]).each do |fund|
      AccountEntryAllocation::IncrementalMigration.new(fund).describe!(apply:)
    rescue StandardError => e
      puts "[fund #{fund.id}] FAILED, nothing changed for this fund: #{e.class}: #{e.message}"
    end
  end

  desc "Take a fund, or every fund in an entity, off incremental allocation (APPLY=true to write)"
  task :disable_incremental, %i[scope id] => :environment do |_t, args|
    apply = ENV["APPLY"] == "true"
    puts apply ? "APPLYING" : "DRY RUN (APPLY=true to write)"
    incremental_funds(args[:scope], args[:id]).each do |fund|
      AccountEntryAllocation::IncrementalMigration.new(fund).disable!(apply:)
    rescue StandardError => e
      puts "[fund #{fund.id}] FAILED, nothing changed for this fund: #{e.class}: #{e.message}"
    end
  end

  # Evaluates each formula with @start_date far in the past — its window covers all history and its own
  # previous value reads zero — and overwrites its stored entry on DATE. No entries are created.
  # The formulas must already sum over @start_date..@end_date, or the stored value is re-added.
  desc "Recompute a formula's stored since-inception entries on a date from full history (DRY_RUN=true to preview)"
  task :reseed_carry_forward, %i[fund_id date sequences] => :environment do |_t, args|
    fund = Fund.find(args[:fund_id])
    formulas = fund.fund_formulas.where(sequence: args[:sequences].split.map(&:to_i)).order(:sequence).to_a
    abort "No formulas found for sequences #{args[:sequences]}" if formulas.empty?

    AccountEntryAllocation::IncrementalMigration.new(fund).reseed!(formulas:, date: Date.parse(args[:date]), apply: ENV["DRY_RUN"] != "true")
  end
end
