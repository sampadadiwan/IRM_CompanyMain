class AggregatePortfolioInvestmentSqlite < ApplicationRecordSqlite
  self.table_name = 'aggregate_portfolio_investments'
  self.primary_key = :id

  include AggregatePortfolioInvestmentShared

  belongs_to :portfolio_company, class_name: 'InvestorSqlite'
  has_many :portfolio_investments, class_name: 'PortfolioInvestmentSqlite', foreign_key: 'aggregate_portfolio_investment_id', dependent: :destroy

  def to_s
    "#{portfolio_company_name}  #{investment_instrument_name}"
  end
end
