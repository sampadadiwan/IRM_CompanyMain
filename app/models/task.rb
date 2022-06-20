class Task < ApplicationRecord
  update_index('task') { self }

  belongs_to :entity
  belongs_to :for_entity, class_name: "Entity", optional: true
  belongs_to :user
  belongs_to :owner, polymorphic: true, optional: true

  scope :completed, -> { where(completed: true) }
  scope :incomplete, -> { where(completed: false) }

  counter_culture :entity, column_name: proc { |t| t.completed ? nil : 'tasks_count' }
end
