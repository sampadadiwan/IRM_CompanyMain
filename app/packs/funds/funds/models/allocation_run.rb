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
  # Only one run per fund at a time: two runs over the same period each delete the other's entries and
  # both insert theirs (runs 3499/3500, fund 316, 2026-11-10 -- docs/modules/allocation/allocation_process.md, "One run per fund at a time").
  # Model-level so the allocate screen, run groups, statement generation and rake tasks all get it.
  validate :fund_not_running_another_allocation, on: :create

  # A run's status is blank until the engine writes one and "Pending" while its formulas run
  UNFINISHED_STATUSES = [nil, "", "Pending"].freeze
  # An unfinished run older than this is taken to have died and no longer blocks the fund; the same
  # cut-off the fund's formula operations use
  STALE_AFTER = FundFormulaOperation::STALE_AFTER
  # Status prefix of a run a user marked as crashed (see mark_crashed!); the engine will not start it
  CRASHED_PREFIX = "Crashed".freeze

  scope :locked, -> { where(locked: true) }
  # Runs that have not finished and are recent enough to still count as running
  scope :unfinished, -> { where(status: UNFINISHED_STATUSES, created_at: STALE_AFTER.ago..) }
  scope :successful, -> { where(status: "Success") }
  scope :pending, -> { where(status: "Pending") }
  scope :overlapping, ->(start_date, end_date) { where("start_date <= ? AND end_date >= ?", end_date, start_date) }

  def self.locked_and_overlapping(fund_id, start_date, end_date)
    where(fund_id:)
      .locked
      .overlapping(start_date, end_date)
      .first
  end

  # The fund's oldest unfinished run, other than `except`, or nil when the fund is free to run
  def self.unfinished_on(fund_id, except: nil)
    scope = unfinished.where(fund_id:)
    # Leave out the run doing the asking (rerun! of a crashed run)
    scope = scope.where.not(id: except) if except
    scope.order(:created_at).first
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

    # Another run on the fund has not finished (or crashed and was never marked): refuse, as a new run would
    busy = AllocationRun.unfinished_on(fund_id, except: id)
    raise ArgumentError, busy.busy_message if busy
    # This run itself is still executing: re-running it now would run it twice at once. A crashed
    # one (unfinished, but no engine on the fund) may be re-run -- that is one way to recover it.
    raise ArgumentError, busy_message if unfinished? && !crashed?

    template_id = statement_template_id
    # Unlocked, and the status cleared so the run reads as in progress as a newly created run does,
    # until the engine records the outcome.
    update_columns(locked: false, status: nil)

    args = [fund_id, start_date, end_date]
    kwargs = { rule_for:, tag_list:, run_allocations:, explain: true, user_id:, generate_soa:, statement_for:, template_id:,
               fund_ratios:, sample: false, allocation_run_id: id }
    now ? AccountEntryAllocationJob.perform_now(*args, **kwargs) : AccountEntryAllocationJob.perform_later(*args, **kwargs)
  end

  # Not finished yet, and recent enough to still count as running (see STALE_AFTER)
  def unfinished?
    UNFINISHED_STATUSES.include?(status) && created_at.present? && created_at > STALE_AFTER.ago
  end

  # Unfinished, but no engine is running on the fund: the process running it died (watchdog,
  # out-of-memory, deploy restart), or its job is still waiting in the queue. Either way it is safe to
  # mark it crashed -- a queued job of a crashed run will not start (AccountEntryAllocation::Engine).
  def crashed?
    unfinished? && !AllocationFundLock.held?(fund_id)
  end

  def crashed_by_user?
    status.to_s.start_with?(CRASHED_PREFIX)
  end

  # Frees the fund after a crash without waiting STALE_AFTER. Refused (false) while an engine is running
  # on the fund -- forcing a live run is exactly how runs 3499/3500 corrupted October -- or once the
  # run has finished. The UPDATE only matches an unfinished status, so two users clicking at once
  # mark it once.
  def mark_crashed!(user)
    return false unless crashed?

    marked = "#{CRASHED_PREFIX}: marked as crashed by #{user.full_name} on #{I18n.l(Time.zone.now, format: :abbr_date_time)}. " \
             "It stopped before finishing; re-run this period."
    AllocationRun.where(id:, status: UNFINISHED_STATUSES).update_all(status: marked, updated_at: Time.current).positive?
  end

  # Why the fund cannot start another run while this one is unfinished, and what to do about it
  def busy_message
    started = "Allocation run #{id} (#{I18n.l(start_date)} – #{I18n.l(end_date)}), started #{I18n.l(created_at, format: :abbr_date_time)} by #{user&.full_name}"
    if crashed?
      "#{started}, has not finished yet and is no longer running. Mark it as crashed under Previous Runs on the Allocate screen, then try again."
    else
      "#{started}, has not finished yet. Wait for it to finish before starting another run on this fund."
    end
  end

  private

  def fund_not_running_another_allocation
    return if fund_id.blank?

    running = AllocationRun.unfinished_on(fund_id)
    errors.add(:base, running.busy_message) if running
  end

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
