class FundUnitSetting < ApplicationRecord
  include WithCustomField
  include ForInvestor

  belongs_to :entity
  belongs_to :fund

  validates :name, length: { maximum: 40 }
  validates_uniqueness_of :name, scope: :fund_id, message: "already exists for this fund"
  validate :allowed_unit_type

  STANDARD_COLUMNS = {
    "Class/Series" => "name",
    "Management Fee %" => "management_fee",
    "Setup Fee %" => "setup_fee",
    "Carry %" => "carry",
    "ISIN" => "isin"
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
