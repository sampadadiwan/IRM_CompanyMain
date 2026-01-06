# Service for listing and filtering KPIs.
#
# This service encapsulates the logic for Ransack search, Pundit scoping,
# and various filters used in the KpisController index action.
#
# It ensures that a policy scope is always applied to the query:
# 1. If a block is given, it yields the relation to the block (allowing controllers to use `policy_scope` helper).
# 2. If no block is given, it uses `Pundit.policy_scope!` directly.
class KpiList
  Result = Struct.new(:q, :kpis, keyword_init: true)

  # @param current_user [User] The user performing the action.
  # @param params [Hash] The parameters for filtering and search.
  # @yield [relation] Optional block for applying policy scope.
  def self.call(current_user, params, &)
    new(current_user, params).call(&)
  end

  def initialize(current_user, params)
    @current_user = current_user
    @params = params
  end

  def call
    # Step 1: Apply Ransack search and policy scope
    @q = Kpi.ransack(@params[:q])
    @kpis = if block_given?
              yield(@q.result)
            else
              Pundit.policy_scope!(@current_user, @q.result)
            end
    @kpis = @kpis.includes(kpi_report: :portfolio_company)

    # Step 2: Standard filters
    filter_params(:import_upload_id)

    Result.new(
      q: @q,
      kpis: @kpis
    )
  end

  private

  def filter_params(*keys)
    keys.each do |key|
      @kpis = @kpis.where(key => @params[key]) if @params[key].present?
    end
  end
end
