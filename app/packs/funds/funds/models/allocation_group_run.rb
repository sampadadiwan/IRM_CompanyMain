# One execution of an AllocationRunTemplateGroup for a period. Recorded as its own record
# with one AllocationGroupRunItem per template (decision 9) so that:
#   - the progress view can show which template is active, done, failed or skipped,
#   - a worker restart continues from the template that was running, not from the top,
#   - "resume from failed template" can reuse the successes of an earlier run (decision 8),
#   - the history survives deletion of the group (group_name is a snapshot, decision 17).
class AllocationGroupRun < ApplicationRecord
  STATUSES = %w[queued running success failed].freeze
  ACTIVE_STATUSES = %w[queued running].freeze

  belongs_to :entity
  belongs_to :user
  belongs_to :allocation_run_template_group, optional: true
  belongs_to :resumed_from, class_name: "AllocationGroupRun", optional: true

  has_many :items, -> { order(:position, :id) }, class_name: "AllocationGroupRunItem",
                                                 dependent: :destroy, inverse_of: :allocation_group_run

  validates :group_name, :start_date, :end_date, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :end_date_after_start_date

  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :finished, -> { where.not(status: ACTIVE_STATUSES) }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_period, ->(start_date, end_date) { where(start_date:, end_date:) }

  # Decision 10(b): one group run per entity at a time.
  def self.active_for_entity(entity_id)
    active.where(entity_id:).order(created_at: :desc).first
  end

  # Decision 10(c): a fund that a running group is using, or has yet to reach, is busy —
  # a manual allocation on it is refused until the group finishes.
  def self.fund_busy?(fund_id)
    AllocationGroupRunItem.joins(:allocation_group_run)
                          .where(allocation_group_runs: { status: ACTIVE_STATUSES })
                          .exists?(fund_id:, status: AllocationGroupRunItem::UNFINISHED_STATUSES)
  end

  def active?
    ACTIVE_STATUSES.include?(status)
  end

  def finished?
    !active?
  end

  def success?
    status == "success"
  end

  def failed?
    status == "failed"
  end

  # Number of items done (any final status) out of the total, for the progress bar.
  # Loads the association once (items.size after items.count{} would issue a COUNT *and*
  # a full SELECT); the association is memoized on this instance, so progress_percent's
  # call into this method reuses the same loaded array rather than querying again.
  def progress
    loaded_items = items.to_a
    total = loaded_items.size
    done = loaded_items.count { |i| AllocationGroupRunItem::FINAL_STATUSES.include?(i.status) }
    [done, total]
  end

  def progress_percent
    done, total = progress
    total.zero? ? 0 : (done * 100 / total)
  end

  def counts_by_status
    items.group_by(&:status).transform_values(&:size)
  end

  def duration
    return nil unless started_at

    (finished_at || Time.current) - started_at
  end

  def to_s
    "#{group_name} · #{I18n.l(start_date)} – #{I18n.l(end_date)}"
  end

  private

  def end_date_after_start_date
    return if start_date.blank? || end_date.blank? || end_date >= start_date

    errors.add(:end_date, "must be on or after the start date")
  end
end
