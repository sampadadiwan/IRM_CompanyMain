class InvestorSqlite < ApplicationRecordSqlite
  self.table_name = 'investors'
  self.primary_key = :id

  include InvestorShared

  has_many :capital_commitments, class_name: 'CapitalCommitmentSqlite', foreign_key: 'investor_id', dependent: :destroy
  has_many :capital_remittances, class_name: 'CapitalRemittanceSqlite', foreign_key: 'investor_id', dependent: :destroy
  has_many :capital_distribution_payments, class_name: 'CapitalDistributionPaymentSqlite', foreign_key: 'investor_id', dependent: :destroy
  has_many :portfolio_investments, class_name: 'PortfolioInvestmentSqlite', foreign_key: 'portfolio_company_id', dependent: :destroy
  has_many :aggregate_portfolio_investments, class_name: 'AggregatePortfolioInvestmentSqlite', foreign_key: 'portfolio_company_id', dependent: :destroy

  def to_s
    "#{investor_name} : #{category}"
  end
end
