class Investment < ApplicationRecord
  include WithCustomField

  CATEGORIES = %w[Founder Self Other Employee].sort.freeze
  TYPES = %w[Equity Convertible].freeze

  belongs_to :portfolio_company, class_name: "Investor"
  belongs_to :entity

  monetize :price_cents, :amount_cents, with_model_currency: :currency

  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :investment_type, presence: true, inclusion: { in: TYPES }
  validates :funding_round, :currency, :investment_date, presence: true
  validates :instrument_name, length: { maximum: 50 }, allow_blank: true

  STANDARD_COLUMNS = { "Portfolio Company" => "portfolio_company_name",
                       "Category" => "category",
                       "Investor Name" => "investor_name",
                       "Investment Type" => "investment_type",
                       "Funding Round" => "funding_round",
                       "Currency" => "currency",
                       "Price" => "price",
                       "Investment Date" => "investment_date",
                       "Amount" => "amount",
                       "Quantity" => "quantity" }.freeze

  def display_category
    category == "Self" ? portfolio_company.entity.name : category
  end

  def to_s
    id.present? ? "#{category} - #{investment_type}" : "New Investment"
  end

  before_save :compute_amount
  def compute_amount
    self.amount_cents = price_cents * quantity
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[category currency funding_round investment_date investment_type investor_name quantity]
  end

  def self.ransackable_associations(_auth_object = nil)
    ["portfolio_company"]
  end
end
