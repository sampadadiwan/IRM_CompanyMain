class TaskRecurrenceRule < ApplicationRecord
  belongs_to :entity
  has_many :tasks, dependent: :destroy

  validates :task_template_payload, presence: true
  validates :rrule, presence: true
  validates :start_date, presence: true

  # The task_template_payload contains attributes like title, details, category, assigned_to_id, etc.
  # This avoids duplicate columns on the master record and allows for flexible task templates.
end
