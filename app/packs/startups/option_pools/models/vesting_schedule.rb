# == Schema Information
#
# Table name: vesting_schedules
#
#  id                :integer          not null, primary key
#  months_from_grant :integer
#  vesting_percent   :integer
#  option_pool_id    :integer          not null
#  entity_id         :integer          not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#

class VestingSchedule < ApplicationRecord
  belongs_to :option_pool, optional: true
  belongs_to :entity
  NESTED_ATTRIBUTES = %i[id months_from_grant vesting_percent _destroy].freeze
  before_validation :set_defaults

  def set_defaults
    self.entity_id = option_pool.entity_id
  end
end
