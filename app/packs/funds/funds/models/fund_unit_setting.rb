class FundUnitSetting < ApplicationRecord
  include WithCustomField
  include ForInvestor

  belongs_to :entity
  belongs_to :fund

  validates :name, length: { maximum: 25 }
  validates_uniqueness_of :name, scope: :fund_id, message: "already exists for this fund"
  validate :allowed_unit_type

  def to_s
    name
  end

  def allowed_unit_type
    errors.add(:name, "#{name} is not allowed. Allowed values: #{fund.unit_types}") unless fund.unit_types.include?(name)
  end
end
