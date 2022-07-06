class Reminder < ApplicationRecord
  belongs_to :entity
  belongs_to :owner, polymorphic: true
  NESTED_ATTRIBUTES = %i[id unit count _destroy].freeze

  before_validation :setup_entity

  def setup_entity
    self.entity_id = owner.entity_id
  end
end
