class VestingSchedule < ApplicationRecord
  belongs_to :option_pool, optional: true
  belongs_to :entity
  NESTED_ATTRIBUTES = %i[id months_from_grant vesting_percent _destroy].freeze
  before_validation :set_defaults

  def set_defaults
    self.entity_id = option_pool.entity_id
  end
end
