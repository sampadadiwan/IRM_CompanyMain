class WorkflowInstance < ApplicationRecord
  belongs_to :folder
  belongs_to :workflow_template
  belongs_to :launched_by, class_name: "User"

  has_many :workflow_actor_responses, dependent: :destroy
  has_many :workflow_state_changes,   dependent: :destroy

  # prefix: avoids .active / .rejected collisions with AR scope conventions
  enum :status, { active: 0, complete: 1, rejected: 2, archived: 3 }, prefix: :instance

  validates :template_snapshot,      presence: true
  validates :current_step_position,  presence: true,
                                     numericality: { only_integer: true, greater_than: 0 }

  # Only one active instance per folder at a time (enforced in service; readable as scope)
  scope :for_folder, ->(folder) { where(folder: folder).order(created_at: :desc) }

  # Returns the current step's data from the frozen snapshot
  def current_step_data
    steps = template_snapshot.with_indifferent_access[:steps] || []
    steps.find { |s| s[:position].to_i == current_step_position }
          &.with_indifferent_access
  end

  # All steps from the snapshot in position order
  def snapshot_steps
    (template_snapshot.with_indifferent_access[:steps] || [])
      .sort_by { |s| s[:position].to_i }
      .map(&:with_indifferent_access)
  end

  # Human-readable snapshot template name
  def template_name
    template_snapshot.with_indifferent_access[:name]
  end
end
