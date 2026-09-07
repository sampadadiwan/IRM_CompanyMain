# One template's slot inside an AllocationGroupRun, in run order. Links to the AllocationRun
# it produced (there is a new one per run, exactly as a manual run) and carries the template
# name and fund as a snapshot so the row still reads after the template is deleted.
class AllocationGroupRunItem < ApplicationRecord
  # pending  — not started yet
  # running  — the engine is on this template now
  # success  — the allocation run finished with status Success (decision 7: only Success counts)
  # failed   — the run errored or ended still Pending; the group stops here
  # skipped  — never reached because an earlier template failed
  # reused   — "resume" kept the success from an earlier run for the same period
  STATUSES = %w[pending running success failed skipped reused].freeze
  UNFINISHED_STATUSES = %w[pending running].freeze
  FINAL_STATUSES = %w[success failed skipped reused].freeze

  belongs_to :allocation_group_run, inverse_of: :items
  belongs_to :allocation_run_template, optional: true
  belongs_to :fund
  belongs_to :allocation_run, optional: true

  validates :template_name, :position, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :ordered, -> { order(:position, :id) }

  def finished?
    FINAL_STATUSES.include?(status)
  end

  def duration
    return nil unless started_at

    (finished_at || Time.current) - started_at
  end
end
