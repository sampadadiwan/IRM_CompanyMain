# == Schema Information
#
# Table name: tasks
#
#  id            :integer          not null, primary key
#  details       :text(65535)
#  entity_id     :integer          not null
#  for_entity_id :integer
#  completed     :boolean          default("0")
#  user_id       :integer          not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  owner_type    :string(255)
#  owner_id      :integer
#  form_type_id  :integer
#

class Task < ApplicationRecord
  update_index('task') { self }

  belongs_to :entity
  belongs_to :for_entity, class_name: "Entity", optional: true
  belongs_to :user
  belongs_to :owner, polymorphic: true, optional: true

  has_many :reminders, as: :owner, dependent: :destroy
  accepts_nested_attributes_for :reminders, allow_destroy: true

  # Customize form
  belongs_to :form_type, optional: true
  serialize :properties, Hash

  scope :completed, -> { where(completed: true) }
  scope :incomplete, -> { where(completed: false) }

  counter_culture :entity, column_name: proc { |t| t.completed ? nil : 'tasks_count' }
end
