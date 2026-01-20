class CapitalDistributionSqlite < ApplicationRecordSqlite
  self.table_name = 'capital_distributions'
  self.primary_key = :id

  include CapitalDistributionShared

  has_many :capital_distribution_payments, class_name: 'CapitalDistributionPaymentSqlite', foreign_key: 'capital_distribution_id', dependent: :destroy
  has_many :portfolio_investments, class_name: 'PortfolioInvestmentSqlite', foreign_key: 'capital_distribution_id'

  def to_s
    title
  end
end
