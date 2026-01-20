class FundUnitSettingSqlite < ApplicationRecordSqlite
  self.table_name = 'fund_unit_settings'
  self.primary_key = :id

  include FundUnitSettingShared

  def to_s
    name
  end
end
