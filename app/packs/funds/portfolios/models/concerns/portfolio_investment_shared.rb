module PortfolioInvestmentShared
  extend ActiveSupport::Concern

  included do
    scope :buys, -> { where("portfolio_investments.quantity > 0") }
    scope :sells, -> { where("portfolio_investments.quantity < 0") }
    scope :conversions, -> { where.not(conversion_date: nil) }
    scope :distributed, -> { where.not(capital_distribution_id: nil) }
    scope :not_distributed, -> { where(capital_distribution_id: nil) }
    scope :for_fund, ->(fund_id) { where(fund_id:) }
    scope :for_portfolio_company, ->(pc_id) { where(portfolio_company_id: pc_id) }
    scope :for_investment_instrument, ->(inst_id) { where(investment_instrument_id: inst_id) }
    scope :for_entity, ->(entity_id) { where(entity_id:) }

    scope :as_of, lambda { |date|
      where(investment_date: ..date)
        .where("conversion_date IS NULL OR conversion_date <= ?", date)
        .order(investment_date: :asc)
    }
    scope :before, lambda { |date|
      where(investment_date: ..date)
        .where("conversion_date IS NULL OR conversion_date <= ?", date)
    }

    scope :non_proforma, -> { where(proforma: false) }
  end
end
