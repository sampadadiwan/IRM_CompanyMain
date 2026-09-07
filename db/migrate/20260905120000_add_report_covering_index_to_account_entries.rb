# Covering index for the Account Entries Period Report
# (docs/technical/account_entry_report_performance.md).
#
# The report's two aggregate passes filter on
#   deleted_at IS NULL AND fund_id = ? AND cumulative = 0 AND reporting_date BETWEEN ? AND ?
# and then read name, capital_commitment_id, commitment_name and amount_cents.
#
# deleted_at is in the key because AccountEntry is paranoid - Trackable calls
# acts_as_paranoid - so `deleted_at IS NULL` is appended to EVERY query. Leaving it out
# would force a row lookup per index entry just to test it, which is exactly the cost
# this index exists to remove.
#
# None of the existing fund indexes can serve that. They are
# [fund_id, entry_type, reporting_date] and [fund_id, name, reporting_date] - with
# entry_type/name sitting between fund_id and reporting_date, a date range for a fund
# cannot be seeked. MySQL prunes to the yearly partition, then walks every row of the
# fund for that year through index_account_entries_on_fund_id, doing a clustered-key
# lookup per row to read cumulative/amount_cents. A one-quarter report reads a year, and
# each lookup touches the wide row (json_fields, notes, explanation).
#
# With this index both passes become index-only range seeks that never touch the row.
#
# Column order: fund_id, cumulative and deleted_at are equality predicates (IS NULL
# counts) so they lead; reporting_date is the range predicate and must come immediately
# after them; the rest are payload, ordered so `name` (the GROUP BY and the pivot's
# column header) is usable for grouping.
#
# OPERATIONAL NOTE: account_entries is very large and partitioned by
# RANGE (YEAR(reporting_date)). Do not run this against production inside a normal
# deploy. Build it with ALGORITHM=INPLACE, LOCK=NONE (as this migration does) during a
# low-traffic window, or with pt-online-schema-change, and add it on the replica first.
# Expect the build to take a while and to need free disk for the new index.
class AddReportCoveringIndexToAccountEntries < ActiveRecord::Migration[8.1]
  INDEX_NAME = "idx_ae_report_fund_cumulative_date".freeze

  INDEX_COLUMNS = %i[fund_id cumulative deleted_at reporting_date name capital_commitment_id commitment_name amount_cents].freeze

  # SQLite (test env) has no ALGORITHM/LOCK clauses and no online DDL; it just builds
  # the index. Only MySQL gets the online-DDL options.
  # See project memory: test runs SQLite, dev/prod run MySQL.
  def mysql?
    connection.adapter_name.match?(/mysql/i)
  end

  def up
    return if index_name_exists?(:account_entries, INDEX_NAME)

    if mysql?
      # Built as a single statement so the ALGORITHM/LOCK clauses apply. add_index would
      # not let us pass them through.
      execute(<<~SQL.squish)
        ALTER TABLE account_entries
          ADD INDEX #{INDEX_NAME} (#{INDEX_COLUMNS.join(', ')}),
          ALGORITHM=INPLACE, LOCK=NONE
      SQL
    else
      add_index :account_entries, INDEX_COLUMNS, name: INDEX_NAME
    end
  end

  def down
    return unless index_name_exists?(:account_entries, INDEX_NAME)

    remove_index :account_entries, name: INDEX_NAME
  end
end
