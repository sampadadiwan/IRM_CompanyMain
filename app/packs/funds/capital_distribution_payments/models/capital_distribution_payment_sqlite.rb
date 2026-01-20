class CapitalDistributionPaymentSqlite < ApplicationRecordSqlite
  self.table_name = 'capital_distribution_payments'
  self.primary_key = :id

  include CapitalDistributionPaymentShared

  belongs_to :capital_distribution, class_name: 'CapitalDistributionSqlite'
  belongs_to :investor, class_name: 'InvestorSqlite'
  belongs_to :capital_commitment, class_name: 'CapitalCommitmentSqlite'
  has_many :fund_units, as: :owner, class_name: 'FundUnitSqlite', dependent: :destroy

  def to_s
    if completed
      "#{investor_name}: #{net_payable} : Completed"
    else
      "#{investor_name}: #{net_payable} : Pending"
    end
  end
end
