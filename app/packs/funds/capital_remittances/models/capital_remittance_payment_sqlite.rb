class CapitalRemittancePaymentSqlite < ApplicationRecordSqlite
  self.table_name = 'capital_remittance_payments'
  self.primary_key = :id

  include CapitalRemittancePaymentShared

  belongs_to :capital_remittance, class_name: 'CapitalRemittanceSqlite'
  belongs_to :investor, class_name: 'InvestorSqlite', optional: true

  def to_s
    "#{investor_name} - #{amount}"
  end
end
