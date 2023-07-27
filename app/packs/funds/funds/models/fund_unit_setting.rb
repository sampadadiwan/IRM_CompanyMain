class FundUnitSetting < ApplicationRecord
  include WithCustomField
  include ForInvestor

  belongs_to :entity
  belongs_to :fund

  validates :name, length: { maximum: 15 }
  validates_uniqueness_of :name, scope: :fund_id, message: "already exists for this fund"

  def to_s
    name
  end
end
