class FundUnitSetting < ApplicationRecord
  include WithCustomField
  include ForInvestor

  belongs_to :entity
  belongs_to :fund

  validates :name, length: { maximum: 15 }

  def to_s
    name
  end
end
