class AllocationRun < ApplicationRecord
  include WithValidationRules

  belongs_to :entity
  belongs_to :fund
  attr_readonly :fund_id # never moves to another fund (funds_api_security_policy_plan.md, B)
  belongs_to :user
  # Set when this run was produced by an allocation run group; nil for a manual run.
  has_one :allocation_group_run_item, dependent: :nullify
  # The allocation run checker's report, at most one per run — re-checking overwrites it.
  has_one :allocation_run_report, dependent: :destroy
  has_one :allocation_group_run, through: :allocation_group_run_item

  # Not persisted. AllocationGroupRunJob sets this when creating a template's own run, so the
  # run isn't blocked by the very group-run item it belongs to (that item's own status is
  # already "running" at the moment its AllocationRun is created — see fund_busy?). Any other
  # caller (a manual run, a rake task, an API endpoint) leaves this false, which is the point:
  # this is model-level, so no future code path can create a run on a fund a group is using
  # without going through this check. WithValidationRules.skip does not exempt it — that skip
  # only silences the rule-engine blocker check (enforce_blocker_rules), not this validation.
  attr_accessor :skip_fund_busy_check

  validates :template_name, length: { maximum: 50 }, allow_blank: true
  validate :fund_not_busy_with_another_group_run, on: :create, unless: :skip_fund_busy_check
  # Allocation writes tracking amounts as it creates account entries. While ChangeTrackingCurrencyJob
  # is rebuilding them (or a failed change awaits a retry) those would be written in whichever
  # currency happens to be saved. Model-level so group runs and rake tasks are covered too.
  validate :fund_not_changing_tracking_currency, on: :create

  scope :locked, -> { where(locked: true) }
  scope :successful, -> { where(status: "Success") }
  scope :pending, -> { where(status: "Pending") }
  scope :overlapping, ->(start_date, end_date) { where("start_date <= ? AND end_date >= ?", end_date, start_date) }

  def self.locked_and_overlapping(fund_id, start_date, end_date)
    where(fund_id:)
      .locked
      .overlapping(start_date, end_date)
      .first
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[end_date fund_ratios generate_soa locked start_date status tag_list template_name user_id].sort
  end

  # No association is searchable; Ransack 6 asks for this list on any non-column condition and raises without it
  def self.ransackable_associations(_auth_object = nil)
    []
  end

  # Runs this allocation again into the same run record, with exactly the settings stored on it,
  # so the period's entries are replaced rather than duplicated under a new run.
  #
  #   AllocationRun.find(3331).rerun!              # queued, like a run started from the screen
  #   AllocationRun.find(3331).rerun!(now: true)   # runs in this console and blocks until done
  #
  # explain and sample are not stored on a run, so they are fixed here at explain: true,
  # sample: false. A locked run is unlocked and re-run; it is not locked again afterwards.
  #
  # Refuses when another locked run overlapping the period still owns entries (re-running would
  # replace that run's figures too), when a run group is using the fund, or when the fund's
  # formulas are being changed -- the same guards as the allocate screen (FundsController#allocate).
  # An older locked run for the same dates that a later run has already replaced owns no entries,
  # so it does not block.
  def rerun!(now: false)
    blocking = AllocationRun.where(fund_id:).where.not(id:).locked.overlapping(start_date, end_date)
                            .find { |run| AccountEntry.exists?(fund_id:, allocation_run_id: run.id) }
    raise ArgumentError, "The period overlaps locked allocation run #{blocking.id} (#{blocking.start_date} to #{blocking.end_date}), which still owns entries." if blocking
    raise ArgumentError, "An allocation run group is currently running on this fund." if AllocationGroupRun.fund_busy?(fund_id)
    raise ArgumentError, "The fund's formulas are being changed. Wait for that to finish." if FundAllocationActivity.formula_operation_applying?(fund)
    raise ArgumentError, "The fund's tracking currency is being changed. Wait for that to finish." if fund.tracking_currency_change_pending?

    template_id = statement_template_id
    # Unlocked, and the status cleared so the run reads as in progress as a newly created run does,
    # until the engine records the outcome.
    update_columns(locked: false, status: nil)

    args = [fund_id, start_date, end_date]
    kwargs = { rule_for:, tag_list:, run_allocations:, explain: true, user_id:, generate_soa:, statement_for:, template_id:,
               fund_ratios:, sample: false, allocation_run_id: id }
    now ? AccountEntryAllocationJob.perform_now(*args, **kwargs) : AccountEntryAllocationJob.perform_later(*args, **kwargs)
  end

  private

  # The run keeps the statement template's name; the job needs its id. Looked up among the same
  # templates the allocate screen offers. Only statement generation uses it, so a name that can't
  # be resolved fails the rerun only when this run generates statements.
  def statement_template_id
    return if template_name.blank?

    templates = fund.capital_commitments.first&.templates(["SOA Template", "Investor Statement Template"]) || []
    matches = templates.select { |d| d.name == template_name }
    return matches.first.id if matches.size == 1
    return unless generate_soa

    raise ArgumentError, "#{matches.empty? ? 'No' : matches.size} statement template#{'s' unless matches.size == 1} named #{template_name.inspect} for this fund."
  end

  def fund_not_busy_with_another_group_run
    return if fund_id.blank? || !AllocationGroupRun.fund_busy?(fund_id)

    errors.add(:base, "An allocation run group is currently running on this fund. Wait for it to finish before starting a manual run.")
  end

  def fund_not_changing_tracking_currency
    return unless fund&.tracking_currency_change_pending?

    errors.add(:base, "The fund's tracking currency is being changed. Wait for that to finish before starting a run.")
  end
end
