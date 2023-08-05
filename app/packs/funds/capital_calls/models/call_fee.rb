class CallFee < ApplicationRecord
  belongs_to :entity
  belongs_to :fund
  belongs_to :capital_call

  NESTED_ATTRIBUTES = %i[id name start_date end_date fee_type notes _destroy].freeze

  before_validation :setup_entity

  def setup_entity
    self.entity_id = capital_call.entity_id
    self.fund_id = capital_call.fund_id
  end
end
