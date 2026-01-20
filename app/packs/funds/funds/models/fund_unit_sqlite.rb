class FundUnitSqlite < ApplicationRecordSqlite
  self.table_name = 'fund_units'
  self.primary_key = :id

  include FundUnitShared

  belongs_to :capital_commitment, class_name: 'CapitalCommitmentSqlite'
  belongs_to :investor, class_name: 'InvestorSqlite'
  belongs_to :owner, polymorphic: true, optional: true

  def to_s
    unit_type
  end
end
