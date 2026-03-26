# Service for listing and filtering KPIs.
#
# This service encapsulates the logic for Ransack search, Pundit scoping,
# and various filters used in the KpisController index action.
#
# It ensures that a policy scope is always applied to the query:
# 1. If a block is given, it yields the relation to the block (allowing controllers to use `policy_scope` helper).
# 2. If no block is given, it uses `Pundit.policy_scope!` directly.
class KpiList < BaseList
  Result = Struct.new(:q, :kpis, :kpi_series, keyword_init: true)

  def call(&)
    @q = Kpi.ransack(@params[:q])
    @kpis = apply_policy_scope(@q.result, &)
    @kpis = @kpis.includes(kpi_report: :portfolio_company)
    @kpis = filter_params(@kpis, :import_upload_id)

    # kpi_series is a relation of distinct rows matching the exact grouping the grid
    # view uses: [name, portfolio_company_id, entity_id, owner_id, tag_list].
    # tag_list lives on kpi_reports so we join it in.
    # unscope(:includes) drops the eager-loads so ActiveRecord doesn't try to
    # hydrate associations on a relation that only selects these five columns.
    @kpi_series = @kpis
                  .unscope(:includes)
                  .joins(:kpi_report)
                  .select("kpis.name, kpis.portfolio_company_id, kpis.entity_id, kpis.owner_id, kpi_reports.tag_list")
                  .distinct
                  .order("kpis.name ASC, kpi_reports.tag_list ASC, kpis.portfolio_company_id ASC, kpis.owner_id ASC")

    Result.new(q: @q, kpis: @kpis, kpi_series: @kpi_series)
  end
end
