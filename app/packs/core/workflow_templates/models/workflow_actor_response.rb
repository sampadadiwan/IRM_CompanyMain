class WorkflowActorResponse < ApplicationRecord
  belongs_to :workflow_instance
  belongs_to :actor, class_name: "User"

  enum :channel, { ui: 0, email_magic_link: 1, auto_reminder: 2 }

  validates :step_position, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :state,         presence: true
  validates :responded_at,  presence: true
  validate  :state_must_be_allowed_for_step

  # An actor may only have one active (non-archived) response per step per instance.
  # Archived responses are kept for audit history; uniqueness only applies to live ones.
  validates :actor_id, uniqueness: {
    scope: [:workflow_instance_id, :step_position],
    conditions: -> { where(archived: false) },
    message: "has already responded to this step"
  }

  scope :active,   -> { where(archived: false) }
  scope :archived, -> { where(archived: true) }
  scope :for_step, ->(position) { where(step_position: position) }

  private

  def state_must_be_allowed_for_step
    return if state.blank?

    step = workflow_instance&.snapshot_steps&.find { |s| s[:position].to_i == step_position.to_i }
    return unless step

    allowed = step[:states].to_s.split(",").map(&:strip).reject(&:blank?)
    return if allowed.empty?

    errors.add(:state, "is not one of the allowed states for this step") unless allowed.include?(state)
  end
end
