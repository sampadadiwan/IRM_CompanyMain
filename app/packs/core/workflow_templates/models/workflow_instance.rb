class WorkflowInstance < ApplicationRecord
  belongs_to :workflowable,       polymorphic: true
  belongs_to :workflow_assignment, optional: true  # nullable — assignment may be removed after launch
  belongs_to :workflow_template
  # entity_id is denormalized and validated below; the association lets WorkflowNotifier (and the
  # shared NotificationExtensions helpers it inherits) reach the entity's settings and sub_domain
  belongs_to :entity, optional: true
  # optional: true because auto-assignment rules launch with no interactive user (system-initiated)
  belongs_to :launched_by, class_name: "User", optional: true

  has_many :workflow_actor_responses, dependent: :destroy
  has_many :workflow_state_changes,   dependent: :destroy

  # prefix: avoids .active / .rejected collisions with AR scope conventions
  enum :status, { active: 0, complete: 1, rejected: 2, archived: 3 }, prefix: :instance

  validates :template_snapshot,      presence: true
  validates :current_step_position,  presence: true,
                                     numericality: { only_integer: true, greater_than: 0 }
  validates :entity_id, presence: true

  # Ordered history of all instances for a given workflowable object
  scope :for_workflowable, ->(obj) { where(workflowable: obj).order(created_at: :desc) }

  # Journeys: instances whose snapshot has a system/acknowledge step (set at launch)
  scope :evaluated, -> { where(evaluated: true) }

  # The last evaluation's result for one step position, e.g. { "status" => "passed", ... }
  def step_result(position)
    (step_results || {})[position.to_s]
  end

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
