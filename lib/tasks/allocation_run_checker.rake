# Generates allocation run checker reports after the fact, for runs that finished long before
# anyone pressed the Check button — or before the checker existed at all.
#
# Nothing about the checks is captured at run time: every one of them is recomputed from the
# ledger, the formulas and the commitments as they stand now. That is what makes a backfill
# possible, and also what limits it — see "How far back is it worth going" below.
#
# Usage:
#   bundle exec rake allocation:check[RUN_ID]              # one run
#   bundle exec rake allocation:check_fund[FUND_ID]        # every run on a fund
#   bundle exec rake allocation:check_fund[FUND_ID] FROM=2025-04-01 TO=2025-12-31
#   bundle exec rake allocation:check_entity[ENTITY_ID]    # every fund in an entity
#
#   ONLY_UNCHECKED=true   skip runs that already have a report (default false — re-checks all)
#   NOW=true              run the checks in this process instead of queueing them
#   DRY_RUN=true          list what would be checked and stop
#
# The reports are attributed to the entity's first company admin, the same as if they had
# pressed Check. Re-checking a run overwrites its existing report; there is never more than one.
#
# ── How far back is it worth going ───────────────────────────────────────────────────────────
#
# Checks 1.2, 1.3 and 2.1 ask "what did THIS run produce?", which needs
# account_entries.allocation_run_id — added 2025-03-29. Check 1.1 needs allocation_runs.status
# — added 2024-07-28. For runs older than those the checker says so and skips the check rather
# than reporting a false failure, so an old run is safe to check, it just answers less.
#
# Checks 1.4, 2.2 and 2.3 read the ledger by fund and period end rather than by run id, so they
# work on a run of any age. On a very old run they are the whole report — and 2.2 (does each
# folio's cumulative still equal the entries beneath it?) is the one worth having: it is the
# check that finds an entry back-dated into a period that was closed years ago.
namespace :allocation do
  # Queues (or runs) the checker for a set of runs and prints what happened.
  def check_allocation_runs(runs, label)
    only_unchecked = ENV["ONLY_UNCHECKED"] == "true"
    inline         = ENV["NOW"] == "true"
    dry_run        = ENV["DRY_RUN"] == "true"

    runs = runs.where.missing(:allocation_run_report) if only_unchecked
    runs = runs.includes(:fund).order(:end_date)
    total = runs.count

    puts "#{label}: #{total} run#{'s' unless total == 1} to check" \
         "#{' (only ones never checked)' if only_unchecked}#{' — DRY RUN' if dry_run}"
    return if total.zero?

    # find_each: a fund with years of history has more runs than is worth loading at once.
    checked = 0
    runs.find_each do |run|
      user = admin_for(run.entity_id)
      if user.nil?
        warn "  [SKIP] run #{run.id}: no user to attribute the report to in entity #{run.entity_id}"
        next
      end

      if dry_run
        puts "  [WOULD CHECK] run #{run.id}  #{run.fund.name}  #{run.start_date} .. #{run.end_date}"
        next
      end

      report = AllocationRunReport.find_or_initialize_by(allocation_run: run)
      report.assign_attributes(entity_id: run.entity_id, fund_id: run.fund_id, user: user,
                               status: "Pending", message: nil, checked_at: nil, json_fields: {})
      report.save!

      if inline
        AllocationRunReportJob.perform_now(report.id)
        report.reload
        puts "  run #{run.id}  #{run.fund.name}  #{run.start_date} .. #{run.end_date}  -> #{report.status}"
      else
        AllocationRunReportJob.perform_later(report.id)
        puts "  run #{run.id}  #{run.fund.name}  #{run.start_date} .. #{run.end_date}  -> queued"
      end
      checked += 1
    end

    puts dry_run ? "Nothing was written." : "#{checked} report#{'s' unless checked == 1} #{inline ? 'built' : 'queued'}."
  end

  # Reports are attributed to a real person so the report page reads sensibly; a company admin
  # is the closest equivalent of whoever would have pressed Check.
  def admin_for(entity_id)
    @admins ||= {}
    @admins[entity_id] ||= User.joins(:roles).where(entity_id: entity_id, roles: { name: "company_admin" }).first ||
                           User.where(entity_id: entity_id).first
  end

  # Narrows a set of runs to a period, if FROM/TO were given.
  def apply_period(runs)
    runs = runs.where(end_date: Date.parse(ENV["FROM"])..) if ENV["FROM"].present?
    runs = runs.where(end_date: ..Date.parse(ENV["TO"])) if ENV["TO"].present?
    runs
  end

  desc "Generate the allocation run checker report for one allocation run"
  task :check, [:run_id] => :environment do |_, args|
    run_id = args[:run_id]&.to_i
    abort "Usage: rake allocation:check[RUN_ID]" if run_id.blank? || run_id.zero?

    run = AllocationRun.find_by(id: run_id)
    abort "AllocationRun #{run_id} not found" if run.nil?

    check_allocation_runs(AllocationRun.where(id: run.id), "Run #{run.id} (#{run.fund.name})")
  end

  desc "Generate allocation run checker reports for every run on a fund"
  task :check_fund, [:fund_id] => :environment do |_, args|
    fund_id = args[:fund_id]&.to_i
    abort "Usage: rake allocation:check_fund[FUND_ID]" if fund_id.blank? || fund_id.zero?

    fund = Fund.find_by(id: fund_id)
    abort "Fund #{fund_id} not found" if fund.nil?

    check_allocation_runs(apply_period(AllocationRun.where(fund_id: fund.id)), "Fund #{fund.name}")
  end

  desc "Generate allocation run checker reports for every run in an entity"
  task :check_entity, [:entity_id] => :environment do |_, args|
    entity_id = args[:entity_id]&.to_i
    abort "Usage: rake allocation:check_entity[ENTITY_ID]" if entity_id.blank? || entity_id.zero?

    entity = Entity.find_by(id: entity_id)
    abort "Entity #{entity_id} not found" if entity.nil?

    check_allocation_runs(apply_period(AllocationRun.where(entity_id: entity.id)), "Entity #{entity.name}")
  end
end
