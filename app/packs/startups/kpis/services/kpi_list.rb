# Service for listing and filtering KPIs.
#
# This service encapsulates the logic for Ransack search, Pundit scoping,
# and various filters used in the KpisController index action.
#
# It ensures that a policy scope is always applied to the query:
# 1. If a block is given, it yields the relation to the block (allowing controllers to use `policy_scope` helper).
# 2. If no block is given, it uses `Pundit.policy_scope!` directly.
class KpiList < BaseList
  Result = Struct.new(:q, :kpis, keyword_init: true)

  def call(&)
    @q = Kpi.ransack(@params[:q])
    @kpis = apply_policy_scope(@q.result, &)
    @kpis = @kpis.includes(kpi_report: :portfolio_company)
    @kpis = filter_params(@kpis, :import_upload_id)

    Result.new(q: @q, kpis: @kpis)
  end
end
