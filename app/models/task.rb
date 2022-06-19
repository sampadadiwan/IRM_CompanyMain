class Task < ApplicationRecord
  belongs_to :entity
  belongs_to :investor, optional: true
  belongs_to :user
  belongs_to :owner, polymorphic: true, optional: true

  scope :completed, -> { where(completed: true) }
  scope :incomplete, -> { where(completed: false) }

  counter_culture :entity, column_name: proc { |t| t.completed ? nil : 'tasks_count' }
end
