Given('I start counting SQL queries against {string} filtered by {string} excluding {string}') do |table, filtered_by, excluding|
  start_counting_sql_queries(table, filtered_by: filtered_by, excluding: excluding)
end

Then('the number of SELECT queries against {string} filtered by {string} excluding {string} should be at most {string}') do |table, filtered_by, excluding, max_count|
  count = stop_counting_sql_queries
  # Assert with the actual count in the failure message so a regression (e.g.
  # reintroducing a per-payment re-query loop) is diagnosable from the Cucumber
  # output alone, without re-running with query logging turned on.
  expect(count).to(be <= max_count.to_i, "expected at most #{max_count} SELECT queries against #{table} filtered by #{filtered_by.inspect} excluding #{excluding.inspect}, got #{count}")
end
