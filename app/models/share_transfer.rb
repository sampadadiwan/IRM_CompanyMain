class ShareTransfer < ApplicationRecord
  TYPES = %w[Transfer Conversion].freeze

  belongs_to :entity
  belongs_to :transfered_by, class_name: "User"

  belongs_to :from_investor, class_name: "Investor", optional: true
  belongs_to :from_user, class_name: "User", optional: true
  belongs_to :from_investment, class_name: "Investment", optional: true

  belongs_to :to_investor, class_name: "Investor"
  belongs_to :to_user, class_name: "User", optional: true
  belongs_to :to_investment, class_name: "Investment"

  validates :transfer_date, :price, :quantity, presence: true
  validates :quantity, comparison: { less_than_or_equal_to: :from_investment_quantity }

  delegate :quantity, to: :from_investment, prefix: true

  validate :check_valid
  def check_valid
    errors.add(:investor, "Investors dont belong to entity") unless investor_valid?
  end

  # This is used by the interactors before processing the transfer
  def pre_validation
    quantity <= from_investment_quantity && investor_valid?
  end

  def investor_valid?
    (from_investor.nil? || from_investor.entity_id == entity_id) &&
      (to_investor.nil? || to_investor.entity_id == entity_id) &&
      (from_investment.nil? || from_investment.entity_id == entity_id) &&
      (to_investment.nil? || to_investment.entity_id == entity_id)
  end
end
