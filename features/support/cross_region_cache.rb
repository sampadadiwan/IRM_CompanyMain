# frozen_string_literal: true

# The test environment runs Rails.cache as :null_store (config/environments/test.rb), where
# every read returns nil and every write - including write(unless_exist: true) - reports
# success. That makes the two cache-backed guarantees in the cross-region hand-off impossible
# to observe: the single-use claim would always appear to win, and the trust-mismatch flag
# would always read back as "no mismatch".
#
# So scenarios that depend on the cache get a real store for their duration.
#
# MemoryStore, not SolidCache: MemoryStore synchronises write(unless_exist: true) under a
# monitor, which is exactly the first-writer-wins semantics the claim relies on, and it does
# not depend on the sqlite test database honouring the row lock that Solid Cache uses on MySQL
# in production. What this therefore proves is the CALLER's behaviour - claim once, refuse
# afterwards, one winner under concurrency. That Solid Cache itself implements unless_exist
# atomically across both of a region's app servers is a property of the store
# (SolidCache::Store::Api#write_entry -> entry_lock_and_write), not of this code.
Around("@cross-region-cache") do |_scenario, block|
  previous = Rails.cache
  Rails.cache = ActiveSupport::Cache::MemoryStore.new
  block.call
ensure
  Rails.cache = previous
end

# SITES and CURRENT_SITE are memoised per process by SiteRegistry, and several scenarios stub
# them. Clearing after every scenario keeps one feature's stub out of the next one's run.
After do
  SiteRegistry.reset!
end
