class FundUnitSetting < ApplicationRecord
  include WithCustomField
  include ForInvestor

  belongs_to :entity
  belongs_to :fund

  def to_s
    name
  end
end
