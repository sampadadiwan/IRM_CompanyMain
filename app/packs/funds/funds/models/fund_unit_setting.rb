class FundUnitSetting < ApplicationRecord
  include WithCustomField
  include ForInvestor
  include FundUnitSettingShared

  belongs_to :entity
  belongs_to :fund

  validates :name, length: { maximum: 40 }
  validates_uniqueness_of :name, scope: :fund_id, message: "already exists for this fund"
  validate :allowed_unit_type

  STANDARD_COLUMNS = {
    "Class/Series; text-col" => "name; text-col",
    "Management Fee %; num-col" => "management_fee; num-col",
    "Setup Fee %; num-col" => "setup_fee; num-col",
    "Carry %; num-col" => "carry; num-col",
    "ISIN; text-col" => "isin; text-col"
  }.freeze

  def to_s
    name
  end

  def allowed_unit_type
    errors.add(:name, "#{name} is not allowed. Allowed values: #{fund.unit_types}") unless fund.unit_types.include?(name)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[created_at management_fee setup_fee carry name isin].sort
  end
end
