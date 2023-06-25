class ShareTransfer < ApplicationRecord
  TYPES = %w[Transfer Conversion].freeze

  belongs_to :entity
  belongs_to :transfered_by, class_name: "User"

  # Share transfer can happen from Investment to Investment or from Holding to Investment
  # Conversion can happen only from Investment to Investment or Holding to Holding
  belongs_to :from_investor, class_name: "Investor", optional: true
  belongs_to :from_investment, class_name: "Investment", optional: true
  belongs_to :to_investor, class_name: "Investor", optional: true
  belongs_to :to_investment, class_name: "Investment", optional: true

  belongs_to :to_holding, class_name: "Holding", optional: true
  belongs_to :from_holding, class_name: "Holding", optional: true
  belongs_to :to_user, class_name: "User", optional: true
  belongs_to :from_user, class_name: "User", optional: true

  validates :transfer_date, :price, :quantity, presence: true
  validates :quantity, comparison: { less_than_or_equal_to: :from_investment_quantity }, if: -> { from_investment.present? }
  validates :quantity, comparison: { less_than_or_equal_to: :from_holding_quantity }, if: -> { from_holding.present? }
  validates :transfer_type, length: { maximum: 10 }

  validate :check_valid
  def check_valid
    errors.add(:investor, "Investors dont belong to entity") unless investor_valid?
  end

  # This is used by the interactors before processing the transfer
  def pre_validation
    quantity_valid? && investor_valid? && holding_valid?
  end

  def quantity_valid?
    (from_investment && quantity <= from_investment_quantity) ||
      (from_holding && quantity <= from_holding_quantity)
  end

  def investor_valid?
    (from_investor.nil? || from_investor.entity_id == entity_id) &&
      (to_investor.nil? || to_investor.entity_id == entity_id) &&
      (from_investment.nil? || from_investment.entity_id == entity_id) &&
      (to_investment.nil? || to_investment.entity_id == entity_id)
  end

  def holding_valid?
    (from_holding.nil? || from_holding.entity_id == entity_id) &&
      (to_holding.nil? || to_holding.entity_id == entity_id)
  end

  def from_holding_quantity
    from_holding.present? ? from_holding.quantity : 0
  end

  def from_investment_quantity
    from_investment.present? ? from_investment.quantity : 0
  end
end
