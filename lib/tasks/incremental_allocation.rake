# Incremental since_inception allocation: move funds onto it, back off it, and correct stored totals.
# See docs/modules/allocation/incremental_allocation_history.md section 12 and AccountEntryAllocation::IncrementalMigration.
#
#   # One fund, or every fund in an entity. Dry run by default: prints the formula edits, blockers,
#   # and the corrected starting values, and changes nothing. APPLY=true does it.
#   bundle exec rake "allocation:enable_incremental[fund,319]"
#   bundle exec rake "allocation:enable_incremental[entity,6349]" APPLY=true
#
#   # Back off: flag off, formulas restored from the audit trail (tracking fixes kept)
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
    date = Date.parse(args[:date])
    dry_run = ENV["DRY_RUN"] == "true"
    formulas = fund.fund_formulas.where(sequence: args[:sequences].split.map(&:to_i)).order(:sequence).to_a
    abort "No formulas found for sequences #{args[:sequences]}" if formulas.empty?

    migration = AccountEntryAllocation::IncrementalMigration.new(fund)
    updated = missing = 0
    migration.with_full_copy do
      formulas.each do |fund_formula|
        puts "\n#{fund_formula.sequence} #{fund_formula.name}"
        migration.since_inception_totals(fund_formula, fund_formula.formula, date).each do |cc_id, total|
          entry = migration.stored_entry(fund_formula, cc_id, date)
          if entry.nil?
            missing += 1
            puts "  commitment #{cc_id}: no stored entry on #{date}, left alone"
            next
          end

          puts format("  commitment %<cc>d: %<old>.2f -> %<new>.2f", cc: cc_id, old: entry.amount_cents / 100, new: total.to_d / 100)
          next if dry_run

          migration.write_stored_total(entry, total)
          updated += 1
        end
      end
    end
    puts "\n#{'DRY RUN, nothing written. ' if dry_run}updated=#{updated} missing=#{missing}"
  end
end
