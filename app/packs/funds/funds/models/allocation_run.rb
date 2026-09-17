class AllocationRun < ApplicationRecord
  include WithValidationRules

  belongs_to :entity
  belongs_to :fund
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

  private

  def fund_not_busy_with_another_group_run
    return if fund_id.blank? || !AllocationGroupRun.fund_busy?(fund_id)

    errors.add(:base, "An allocation run group is currently running on this fund. Wait for it to finish before starting a manual run.")
  end
end
