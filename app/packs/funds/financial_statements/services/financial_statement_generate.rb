# Starts (or restarts) the statements run for a fund and period: a new allocation run tagged
# "Financial Statements" that runs only the fund's statement formula. Refuses, with a message the
# user sees, in this order:
#   X3  the period's statements are locked
#   E28 another statement set ends on the same date
#   X2  an allocation run is in progress on the fund (also stops double-clicks, E25)
#   X1  no successful accounting run covers the period
#   X15 the statement formula is missing or disabled
#   X16 a locked statements run overlaps the end date
# Allowed over a locked accounting run (H14): the statements run replaces only its own lines.
# The allocate screen's own lock check (FundsController#allocate, AllocationRun.locked_and_overlapping)
# is untouched, so an ordinary run on a locked period is still blocked (X4).
# A new AllocationRun per Generate: AllocationRun#rerun! refuses whenever a locked run overlaps,
# which is always true here. The run's dates are the end date only (card ④ rule 1).
# Worked examples H12, H14, E1, E25, E28, X1, X2, X3, X4, X15, X16 —
# openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementGenerate
  class Refused < StandardError; end

  # A run created this recently with no status yet is treated as queued
  QUEUED_WINDOW = 2.hours
  # A run still "Pending" after this long is taken to have died (its job was killed), so it no longer
  # blocks Generate forever
  PENDING_WINDOW = 12.hours

  def self.call(...)
    new(...).call
  end

  # Preconditions as the Generate popup shows them, by the same rules the guards use
  # { run_in_progress:, formula_enabled:, latest_accounting_run: } — the covering run depends on the
  # dates the user picks, so the popup names the latest completed one instead
  def self.preconditions(fund)
    runs = AllocationRun.where(fund_id: fund.id)
    {
      run_in_progress: run_in_progress?(runs),
      formula_enabled: FundFormula.exists?(fund_id: fund.id, rule_type: "GenerateFinancialStatementLines", enabled: true),
      latest_accounting_run: accounting_runs(runs).order(end_date: :desc, created_at: :desc).first
    }
  end

  # Running now, or created moments ago and still queued (status not set yet); a "Pending" run older
  # than PENDING_WINDOW is taken to have died
  def self.run_in_progress?(runs)
    runs.exists?(status: "Pending", created_at: PENDING_WINDOW.ago..) || runs.exists?(status: nil, created_at: QUEUED_WINDOW.ago..)
  end

  # Successful accounting runs (statements runs excluded)
  def self.accounting_runs(runs)
    runs.successful.where("tag_list IS NULL OR tag_list NOT LIKE ?", "%#{FundFormula::FINANCIAL_STATEMENTS_TAG}%")
  end

  def initialize(fund:, start_date:, end_date:, user:)
    @fund = fund
    @start_date = start_date
    @end_date = end_date
    @user = user
  end

  def call
    raise Refused, "Enter a start date on or before the end date." if @start_date.nil? || @end_date.nil? || @start_date > @end_date

    # Assigned inside the lock, used after it
    statement = nil
    run = nil
    # Fund row lock: two clicks or two users can't both pass the in-progress guard (E25)
    @fund.with_lock do
      # The existing set for exactly this period, if any (E1)
      statement = FinancialStatement.find_by(fund_id: @fund.id, start_date: @start_date, end_date: @end_date)
      # X3, E28, X2, X15, X16 — raises Refused
      guard!(statement)
      # X1 — the run the statements are "built from". H14: a locked accounting run is fine; X4: the
      # allocate screen's own lock check is not touched, so ordinary runs stay blocked
      accounting_run = covering_accounting_run
      # A fresh run every time (rerun! is blocked by the locked accounting run)
      run = create_run!

      # First generation of this period creates the record
      statement ||= FinancialStatement.new(fund: @fund, entity_id: @fund.entity_id, start_date: @start_date, end_date: @end_date)
      # E1: regenerating a draft reuses the record; the frozen copy of a demoted set is kept
      statement.update!(status: "draft", accounting_allocation_run: accounting_run, statements_allocation_run: run,
                        refreshed_at: nil, checks: nil, unmapped_count: 0)
    end

    # Enqueued after the commit: the job's scratch load reads the database from another process
    AccountEntryAllocationJob.perform_later(@fund.id, @end_date, @end_date, user_id: @user.id, run_allocations: true, explain: true,
                                                                            generate_soa: false, fund_ratios: false, sample: false, rule_for: nil,
                                                                            tag_list: FundFormula::FINANCIAL_STATEMENTS_TAG, allocation_run_id: run.id)
    Rails.logger.info { "FinancialStatementGenerate: fund #{@fund.id} statement #{statement.id} run #{run.id} #{@start_date}..#{@end_date}" }
    statement
  end

  private

  def guard!(statement)
    # X3
    raise Refused, "These statements are locked." if statement&.locked?

    # E28: statement lines are dated on the end date, so two sets can't share one
    same_end = FinancialStatement.where(fund_id: @fund.id, end_date: @end_date).where.not(start_date: @start_date).first
    if same_end
      raise Refused, "Statements ending #{I18n.l(@end_date)} already exist (#{same_end.period_label}). " \
                     "Open them instead; their year-to-date column covers this period."
    end

    # X2 / E25
    raise Refused, "An allocation run is in progress for this fund. Try again when it finishes." if run_in_progress?

    # X15
    formula = FundFormula.find_by(fund_id: @fund.id, rule_type: "GenerateFinancialStatementLines")
    raise Refused, "Enable the fund's financial statement formula first." unless formula&.enabled

    # X16: a locked statements run on this date would block the engine's delete of its lines
    locked_fs_run = AllocationRun.where(fund_id: @fund.id).locked.overlapping(@end_date, @end_date)
                                 .exists?(["tag_list LIKE ?", "%#{FundFormula::FINANCIAL_STATEMENTS_TAG}%"])
    raise Refused, "Unlock the statements run for this period first." if locked_fs_run
  end

  def run_in_progress?
    self.class.run_in_progress?(AllocationRun.where(fund_id: @fund.id))
  end

  # X1: the latest successful accounting run (not a statements run) covering the whole period
  def covering_accounting_run
    run = self.class.accounting_runs(AllocationRun.where(fund_id: @fund.id))
              .where(start_date: ..@start_date, end_date: @end_date..)
              .order(created_at: :desc).first
    raise Refused, "Run and complete the fund's allocations for this period first." unless run

    run
  end

  # Model validations (a run group using the fund, a tracking-currency change) surface as refusals
  def create_run!
    WithValidationRules.skip do
      AllocationRun.create!(entity_id: @fund.entity_id, fund_id: @fund.id, start_date: @end_date, end_date: @end_date,
                            run_allocations: true, generate_soa: false, fund_ratios: false, user_id: @user.id,
                            tag_list: FundFormula::FINANCIAL_STATEMENTS_TAG)
    end
  rescue ActiveRecord::RecordInvalid => e
    raise Refused, e.record.errors.full_messages.to_sentence
  end
end
