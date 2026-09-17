# Lightweight SQL query counter for Cucumber scenarios that need to assert on the
# NUMBER of queries issued against a table, not just on behavior — used to catch
# performance/memory regressions (e.g. a per-iteration re-query loop) that a purely
# functional assertion can't see.
#
# `filtered_by`, when given, requires the column to appear as an actual WHERE
# predicate (`"col" = ?`), not just anywhere in the SQL text — a plain substring
# match is too loose: e.g. SQLite's ALTER-TABLE-via-recreate dance (triggered once
# per fresh test DB, when maintain_test_schema! rebuilds a table to fix a column
# type) emits `SELECT "id","capital_commitment_id","capital_distribution_id",... FROM
# "capital_distribution_payments"` with no WHERE at all — the column name shows up
# only because it's being copied, not filtered on — and a bare substring check would
# wrongly count that as a "filtered by capital_distribution_id" query.
#
# `excluding`, when given, drops queries containing that substring — for isolating
# one query shape from other, legitimately-per-row queries against the same table
# and column (e.g. a per-record uniqueness check) that would otherwise dilute the
# signal you're trying to assert on.
module SqlQueryCounter
  def start_counting_sql_queries(table, filtered_by: nil, excluding: nil)
    @sql_query_count = 0
    @sql_query_subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      sql = payload[:sql].to_s
      next unless sql.match?(/\ASELECT/i)
      next unless sql.match?(/#{Regexp.escape(table)}/i)
      next if filtered_by && !sql.match?(/"#{Regexp.escape(filtered_by)}"\s*=\s*\?/)
      next if excluding && sql.include?(excluding)

      @sql_query_count += 1
    end
  end

  # Unsubscribes (so counting doesn't leak into later steps) and returns the tally.
  def stop_counting_sql_queries
    ActiveSupport::Notifications.unsubscribe(@sql_query_subscriber) if @sql_query_subscriber
    @sql_query_subscriber = nil
    @sql_query_count
  end
end

World(SqlQueryCounter)
