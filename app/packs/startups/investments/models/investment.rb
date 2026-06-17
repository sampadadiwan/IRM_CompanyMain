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
  validates :funding_round, length: { maximum: 40 }
  validates :currency, length: { maximum: 3 }

  STANDARD_COLUMNS = { "Portfolio Company; text-col" => "portfolio_company_name; text-col",
                       "Category; text-col" => "category; text-col",
                       "Investor Name; text-col" => "investor_name; text-col",
                       "Investment Type; text-col" => "investment_type; text-col",
                       "Funding Round; text-col" => "funding_round; text-col",
                       "Currency; text-col" => "currency; text-col",
                       "Price; num-col" => "price; num-col",
                       "Investment Date; date-col" => "investment_date; date-col",
                       "Amount; num-col" => "amount; num-col",
                       "Quantity; num-col" => "quantity; num-col" }.freeze

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
