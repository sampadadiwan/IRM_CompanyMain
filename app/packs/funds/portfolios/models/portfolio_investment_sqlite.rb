class PortfolioInvestmentSqlite < ApplicationRecordSqlite
  self.table_name = 'portfolio_investments'
  self.primary_key = :id

  include PortfolioInvestmentShared

  belongs_to :portfolio_company, class_name: 'InvestorSqlite'
  belongs_to :aggregate_portfolio_investment, class_name: 'AggregatePortfolioInvestmentSqlite'
  belongs_to :capital_commitment, class_name: 'CapitalCommitmentSqlite', optional: true
  belongs_to :capital_distribution, class_name: 'CapitalDistributionSqlite', optional: true

  has_many :account_entries, -> { where(parent_type: "PortfolioInvestment") }, class_name: 'AccountEntrySqlite', foreign_key: :parent_id

  def to_s
    "#{portfolio_company_name} #{investment_instrument_name} #{buy_sell} #{I18n.l(investment_date)}"
  end
end
