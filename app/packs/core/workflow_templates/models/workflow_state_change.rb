class WorkflowStateChange < ApplicationRecord
  belongs_to :workflow_instance
  belongs_to :actor, class_name: "User", optional: true # nil for system-generated events

  enum :channel, { ui: 0, email_magic_link: 1, auto_reminder: 2, system: 3 }

  validates :step_position, presence: true
  validates :to_state,      presence: true

  scope :for_step, ->(position) { where(step_position: position) }
  scope :chronological, -> { order(:created_at) }
end
