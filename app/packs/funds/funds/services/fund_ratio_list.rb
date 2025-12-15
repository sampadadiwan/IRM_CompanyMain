# Service for listing and filtering Fund Ratios.
#
# This service encapsulates the logic for Ransack search, Pundit scoping,
# search refinements, and pivot grouping used in the FundRatiosController index action.
#
# It ensures that a policy scope is always applied to the query:
# 1. If a block is given, it yields the relation to the block (allowing controllers to use `policy_scope` helper).
# 2. If no block is given, it uses `Pundit.policy_scope!` directly.
class FundRatioList
  Result = Struct.new(:q, :fund_ratios, :fund, :pivot, keyword_init: true)

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
    # Step 1: Perform Ransack search
    @q = FundRatio.ransack(@params[:q])
    @fund_ratios = if block_given?
                     yield(@q.result)
                   else
                     Pundit.policy_scope!(@current_user, @q.result)
                   end
    @fund_ratios = @fund_ratios.includes(:fund, :capital_commitment, :portfolio_scenario)

    @fund_ratios = FundRatioSearch.perform(@fund_ratios, @current_user, @params)

    @fund = Fund.find(@params[:fund_id]) if @params[:fund_id].present?

    # Step 3: Apply additional filters
    filter_params(
      :import_upload_id,
      :capital_commitment_id,
      :portfolio_scenario_id,
      :owner_type,
      :owner_id,
      :scenario,
      :valuation_id,
      :fund_id
    )

    # Step 4: Special filters with more specific logic
    @fund_ratios = @fund_ratios.where(capital_commitment_id: nil) if @params[:fund_ratios_only].present?
    @fund_ratios = @fund_ratios.where(latest: true) if @params[:latest] == "true"

    result_attrs = { q: @q, fund_ratios: @fund_ratios, fund: @fund }

    # Step 5: Pivot grouping (if requested)
    if @params[:pivot].present?
      group_by_period = @params[:group_by_period] || :quarter
      result_attrs[:pivot] = FundRatioPivot.new(@fund_ratios.includes(:fund), group_by_period:).call
    end

    Result.new(result_attrs)
  end

  private

  def filter_params(*keys)
    keys.each do |key|
      @fund_ratios = @fund_ratios.where(key => @params[key]) if @params[key].present?
    end
  end
end
