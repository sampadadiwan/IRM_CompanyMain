# A named, ordered list of AllocationRunTemplates — "Quarterly close", "Annual close" — that
# is run as one unit for a period. Templates run strictly one after another in position
# order, so a master fund can be placed before its feeders.
class AllocationRunTemplateGroup < ApplicationRecord
  belongs_to :entity
  belongs_to :user

  has_many :items, -> { order(:position, :id) }, class_name: "AllocationRunTemplateGroupItem",
                                                 dependent: :destroy, inverse_of: :allocation_run_template_group
  has_many :allocation_run_templates, through: :items
  # History outlives the group: runs keep a snapshot of the group name (decision 17).
  has_many :allocation_group_runs, dependent: :nullify

  accepts_nested_attributes_for :items, allow_destroy: true

  validates :name, presence: true, length: { maximum: 100 }, uniqueness: { scope: :entity_id }
  validate :has_at_least_one_template

  scope :ordered, -> { order(:name) }

  # Items with their template and fund preloaded, in run order.
  def ordered_items
    items.includes(allocation_run_template: :fund)
  end

  # The run currently queued or in progress for this group, if any.
  def active_run
    allocation_group_runs.active.order(created_at: :desc).first
  end

  def latest_run
    allocation_group_runs.order(created_at: :desc).first
  end

  def to_s
    name
  end

  private

  def has_at_least_one_template
    return if items.reject(&:marked_for_destruction?).any?

    errors.add(:base, "Add at least one allocation run template to the group")
  end
end
