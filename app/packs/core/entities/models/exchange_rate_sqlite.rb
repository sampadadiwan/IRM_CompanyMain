class ExchangeRateSqlite < ApplicationRecordSqlite
  self.table_name = 'exchange_rates'
  self.primary_key = :id

  include ExchangeRateShared
end
