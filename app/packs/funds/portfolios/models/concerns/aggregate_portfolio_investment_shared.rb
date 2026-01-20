module AggregatePortfolioInvestmentShared
  extend ActiveSupport::Concern

  included do
    scope :for_fund, ->(fund_id) { where(fund_id:) }
  end
end
