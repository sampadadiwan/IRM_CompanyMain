class FundSqlite < ApplicationRecordSqlite
  self.table_name = 'funds'
  self.primary_key = :id

  include FundShared

  has_many :capital_commitments, class_name: 'CapitalCommitmentSqlite', foreign_key: :fund_id
  has_many :account_entries, class_name: 'AccountEntrySqlite', foreign_key: :fund_id
  alias account_entries_sqlite account_entries
  has_many :fund_unit_settings, class_name: 'FundUnitSettingSqlite', foreign_key: :fund_id
end
