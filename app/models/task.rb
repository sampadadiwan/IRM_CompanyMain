class Task < ApplicationRecord
  belongs_to :entity
  belongs_to :investor
  belongs_to :user
  belongs_to :owner, polymorphic: true

  counter_culture :entity, column_name: proc { |t| t.completed ? nil : 'tasks_count' }
end
