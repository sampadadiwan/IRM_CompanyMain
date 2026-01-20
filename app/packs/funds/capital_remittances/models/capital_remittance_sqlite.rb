class CapitalRemittanceSqlite < ApplicationRecordSqlite
  self.table_name = 'capital_remittances'
  self.primary_key = :id

  include CapitalRemittanceShared

  belongs_to :capital_commitment, class_name: 'CapitalCommitmentSqlite'
  belongs_to :investor, class_name: 'InvestorSqlite'
  has_many :capital_remittance_payments, class_name: 'CapitalRemittancePaymentSqlite', foreign_key: 'capital_remittance_id', dependent: :destroy
  has_many :fund_units, as: :owner, class_name: 'FundUnitSqlite', dependent: :destroy

  def to_s
    "#{investor_name}: #{folio_id}"
  end
end
