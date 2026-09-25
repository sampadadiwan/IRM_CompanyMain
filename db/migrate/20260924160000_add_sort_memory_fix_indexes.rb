class AddSortMemoryFixIndexes < ActiveRecord::Migration[8.1]
  # Squashed from five separate same-day migrations (20260924120000/123000/130000/140000/150000)
  # that accumulated during one debugging session into the "Out of sort memory" errors on the KPI
  # grid, KpiCumulateJob, and KpiWorkbookReader - each index below was added and verified against a
  # real EXPLAIN plan or a live backtrace one at a time; splitting them into one file each (and one
  # per table) made sense mid-investigation but bloats the PR diff now that the story is settled.
  # See git history on this filename's five predecessors for the migration-by-migration narrative
  # if needed.
  #
  # Written as up/down rather than `change` so the guards don't silently break rollback: inside a
  # reverted `change`, `index_exists?` is evaluated against a database that still HAS the index, so
  # every `unless index_exists?` body is skipped, nothing is recorded to invert, and `db:rollback`
  # becomes a no-op. The guards themselves are needed to stay runnable against a database that
  # already has some/all of these from the original five migrations (staging and this session's dev
  # DB both do) - without them add_index raises "Duplicate key name" the first time this version
  # runs there. Same up/down + guard shape as
  # 20260905120000_add_report_covering_index_to_account_entries.rb.
  INDEXES = [
    # No index on as_of at all previously, so every ORDER BY as_of (KpiReportSearch, the KPI grid,
    # Kpi#find_prior_period_kpi/#find_next_period_kpi) was a filesort over the full, wide
    # (text/json-heavy) row set - the direct cause of the "Out of sort memory" errors this session
    # was fixing. Helps any as_of-only filter/sort; the composites below cover the common case
    # where a WHERE filter also competes for the optimizer's index choice.
    [:kpi_reports, %i[as_of], "index_kpi_reports_on_as_of"],

    # The plain as_of index above isn't enough for the KPI grid's actual query: it's always
    # filtered by portfolio_company_id or entity_id first, and MySQL prefers whichever index is
    # most selective for that WHERE over the as_of index, so ORDER BY as_of still fell back to a
    # filesort (confirmed via EXPLAIN: "Using filesort" persisted with only the plain as_of index).
    # Leading each composite with the column the grid actually filters by lets MySQL satisfy the
    # WHERE and return rows already in as_of order from the same index scan (re-confirmed via
    # EXPLAIN after adding these). Doesn't help the "portfolio_company_id = ? OR entity_id = ?"
    # shape (KpiReportSearch#filter_by_portfolio_company) - that still index-merges and can't
    # preserve sort order, so the grid view sorts in Ruby after a single unordered load instead
    # (see _grid_view.html.erb).
    [:kpi_reports, %i[portfolio_company_id as_of], "index_kpi_reports_on_portfolio_company_id_and_as_of"],
    [:kpi_reports, %i[entity_id as_of], "index_kpi_reports_on_entity_id_and_as_of"],

    # KpiWorkbookReader#find_or_create_kpi_report's `.first_or_create` (its find half) filters
    # kpi_reports by entity_id + portfolio_company_id + as_of + period + tag_list together - the
    # report's effective natural key - once per distinct period+tag combination in the uploaded
    # workbook, i.e. potentially hundreds of times per import. Neither the as_of composites above
    # nor the single-column indexes were enough on their own to stop MySQL merging two of them for
    # this 5-column WHERE (confirmed via EXPLAIN: still index_merge/intersect with both in place).
    # This one is confirmed via a real staging backtrace landing on exactly this line to be the
    # actual "Out of sort memory" source: an intermittent failure after upload/reject-all/re-upload
    # cycles that stops partway through a workbook once the merge's underlying algorithm tips over,
    # not something reproducible on a small dev dataset. A single composite covering the query's
    # full equality shape gives MySQL a direct, unambiguous match (confirmed via EXPLAIN: type
    # "ref", all 5 columns used, no merge).
    #
    # This also serves KpiWorkbookReader#report_statuses (memoized, once per import), which filters
    # by entity_id AND portfolio_company_id only and previously index_merged them: those are this
    # index's two leading columns, so no separate [portfolio_company_id, entity_id] index is needed
    # - an earlier revision of this migration added one, which was pure write overhead on a table
    # bulk-inserted by every import.
    [:kpi_reports, %i[portfolio_company_id entity_id as_of period tag_list], "index_kpi_reports_on_natural_key"],

    # KpiCumulateJob (KpiCumulative#fetch_related_monthly_kpis/#fetch_related_quarterly_kpis) queries
    # entity.kpis.approved.where(name:, portfolio_company_id:) joined to kpi_reports, and Kpi's own
    # find_prior_period_kpi/find_next_period_kpi (used by the RAG recompute that fires on approval)
    # query Kpi.approved.where(name:, portfolio_company_id:) directly - both fired in bulk from
    # KpisController#approve_all, which is exactly where the "Out of sort memory" reports came from.
    # With only single-column indexes on kpis, MySQL fell back to index_merge intersect (combining
    # the entity_id and portfolio_company_id indexes), which requires building a temporary table
    # across every one of that entity/company's kpis - across every period and every KPI name -
    # before the name/status filters ever narrow it down (confirmed via EXPLAIN:
    # "Using intersect(...); Using temporary; Using filesort" on the kpis row). Composites covering
    # both queries' equality filters let MySQL satisfy the WHERE with a single direct index lookup
    # instead (re-confirmed via EXPLAIN: type "ref"), cutting the candidate row count from "every
    # kpi for this entity/company" down to single digits before the join to kpi_reports and its
    # (comparatively trivial, few-row) final ORDER BY kpi_reports.as_of sort.
    [:kpis, %i[entity_id portfolio_company_id status name], "index_kpis_on_entity_pc_status_name"],
    [:kpis, %i[portfolio_company_id name status], "index_kpis_on_pc_name_status"]
  ].freeze

  def up
    INDEXES.each do |table, columns, name|
      next if index_name_exists?(table, name)

      add_index table, columns, name: name
    end
  end

  def down
    INDEXES.reverse_each do |table, _columns, name|
      next unless index_name_exists?(table, name)

      remove_index table, name: name
    end
  end
end
