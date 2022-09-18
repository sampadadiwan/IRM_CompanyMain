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
end
