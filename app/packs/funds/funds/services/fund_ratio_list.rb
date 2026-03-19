# Service for listing and filtering Fund Ratios.
#
# This service encapsulates the logic for Ransack search, Pundit scoping,
# search refinements, and pivot grouping used in the FundRatiosController index action.
#
# It ensures that a policy scope is always applied to the query:
# 1. If a block is given, it yields the relation to the block (allowing controllers to use `policy_scope` helper).
# 2. If no block is given, it uses `Pundit.policy_scope!` directly.
class FundRatioList < BaseList
  Result = Struct.new(:q, :fund_ratios, :fund, :pivot, keyword_init: true)

  def call(&)
    @q = FundRatio.ransack(@params[:q])
    @fund_ratios = apply_policy_scope(@q.result, &)

    @fund_ratios = @fund_ratios.includes(:fund, :capital_commitment, :portfolio_scenario)

    @fund_ratios = FundRatioSearch.perform(@fund_ratios, @current_user, @params)

    @fund = Fund.find(@params[:fund_id]) if @params[:fund_id].present?

    # Apply additional filters
    @fund_ratios = filter_params(@fund_ratios,
                                 :import_upload_id,
                                 :capital_commitment_id,
                                 :portfolio_scenario_id,
                                 :owner_type,
                                 :owner_id,
                                 :scenario,
                                 :valuation_id,
                                 :fund_id,
                                 :name)

    # Step 3.5: Filter by scenarios if provided (can be comma-separated list of names)
    if @params[:scenarios].present? && @params[:scenarios] != "true"
      scenario_names = @params[:scenarios].split(",").map(&:strip)
      @fund_ratios = @fund_ratios.where(scenario: scenario_names)
    end

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
end
