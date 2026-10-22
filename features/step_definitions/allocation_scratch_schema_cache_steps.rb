# Steps for features/fund/allocation_scratch_schema_cache.feature.
#
# Every scratch SQLite database the allocation engine uses is reached through ApplicationRecordSqlite's one
# connection pool (WithScratchSqlite swaps the scratch connection in per thread), so they share one schema
# cache. That pool is established against an empty in-memory database: anything that asks the cache about
# account_entries while no scratch database is swapped in gets "no such table" - and Rails caches that.

# The innocent lookup that poisons it: the same question insert_all asks, asked outside a scratch database
Given("the allocation engine's schema cache was read outside a scratch database") do
  expect(Thread.current[:sqlite_scratch_connection]).to be_nil
  ApplicationRecordSqlite.connection_pool.schema_cache.data_source_exists?("account_entries")
end
