class Investment < ApplicationRecord
  CATEGORIES = %w[Founder Self Other Employee].sort.freeze
  TYPES = %w[Equity Convertible].freeze

  belongs_to :portfolio_company, class_name: "Investor"
  belongs_to :entity

  monetize :price_cents, :amount_cents, with_model_currency: :currency

  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :investment_type, presence: true, inclusion: { in: TYPES }
  validates :funding_round, :currency, :investment_date, presence: true

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

  def self.generate_cap_table(funding_rounds, portfolio_company_id, group_by_field: :investor_name)
    # Get all investments for the funding round
    investments = where(funding_round: funding_rounds, portfolio_company_id: portfolio_company_id)

    # Separate equity and convertible investments
    equity_investments = investments.where(investment_type: "Equity")
    convertible_investments = investments.where(investment_type: "Convertible")

    # Compute current holdings (excluding convertibles)
    current_holdings = equity_investments.group(group_by_field).sum(:quantity)

    # Compute total convertibles for each investor
    convertibles = convertible_investments.group(group_by_field).sum(:quantity)

    # Merge both hashes to get all unique investors
    all_investors = (current_holdings.keys + convertibles.keys).uniq

    # Compute total outstanding shares for percentage calculations
    total_equity = current_holdings.values.sum
    total_fully_diluted = total_equity + convertibles.values.sum

    # **Handle case where only convertibles exist**
    total_equity = total_fully_diluted if total_equity.zero?

    return [] if total_fully_diluted.zero?

    # Generate the cap table
    cap_table = all_investors.map do |grouping_field|
      equity_quantity = current_holdings[grouping_field] || 0
      convertible_quantity = convertibles[grouping_field] || 0
      diluted_quantity = equity_quantity + convertible_quantity

      percentage = total_equity.positive? ? (equity_quantity.to_f / total_equity * 100).round(1) : 0.0
      fully_diluted_percentage = (diluted_quantity.to_f / total_fully_diluted * 100).round(1)

      {
        grouping_field: grouping_field,
        quantity: equity_quantity,
        percentage: "#{percentage}%",
        fully_diluted: diluted_quantity,
        fully_diluted_percentage: "#{fully_diluted_percentage}%"
      }
    end

    # Append total row
    cap_table << {
      grouping_field: "Total",
      quantity: total_equity,
      percentage: "100.0%",
      fully_diluted: total_fully_diluted,
      fully_diluted_percentage: "100.0%"
    }

    cap_table
  end
end
