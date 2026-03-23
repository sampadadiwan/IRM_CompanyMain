class CapitalCommitmentSqlite < ApplicationRecordSqlite
  self.table_name = 'capital_commitments'
  self.primary_key = :id

  include CapitalCommitmentShared

  belongs_to :investor, optional: true, class_name: 'InvestorSqlite'
  belongs_to :fund, optional: true, class_name: 'FundSqlite'
  belongs_to :feeder_fund, optional: true, class_name: 'FundSqlite'

  has_many :account_entries, class_name: 'AccountEntrySqlite', foreign_key: 'capital_commitment_id', dependent: :destroy
  has_many :capital_remittances, class_name: 'CapitalRemittanceSqlite', foreign_key: 'capital_commitment_id', dependent: :destroy
  has_many :capital_remittance_payments, through: :capital_remittances, source: :capital_remittance_payments
  has_many :capital_distribution_payments, class_name: 'CapitalDistributionPaymentSqlite', foreign_key: 'capital_commitment_id', dependent: :destroy
  has_many :fund_units, class_name: 'FundUnitSqlite', foreign_key: 'capital_commitment_id', dependent: :destroy
  has_many :commitment_adjustments, class_name: 'CommitmentAdjustmentSqlite', foreign_key: 'capital_commitment_id', dependent: :destroy

  def to_s
    "#{investor_name}, Folio: #{folio_id}"
  end
end
