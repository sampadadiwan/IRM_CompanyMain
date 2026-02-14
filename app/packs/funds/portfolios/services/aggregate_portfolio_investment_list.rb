# Service for listing and filtering Aggregate Portfolio Investments.
#
# This service encapsulates the logic for Ransack search (including snapshot handling),
# Pundit scoping, standard filters, search refinements, and view modes (Time Series).
#
# It ensures that a policy scope is always applied to the query:
# 1. If a block is given, it yields the relation to the block (allowing controllers to use `policy_scope` helper).
# 2. If no block is given, it uses `Pundit.policy_scope!` directly.
class AggregatePortfolioInvestmentList < BaseList
  Result = Struct.new(:q, :aggregate_portfolio_investments, :time_series, :fields, :show_fund_name, keyword_init: true)

  def call(&)
    initialize_query
    @aggregate_portfolio_investments = apply_policy_scope(@q.result, &)
    @aggregate_portfolio_investments = @aggregate_portfolio_investments.joins(:investment_instrument).includes(:fund, :portfolio_company, :investment_instrument)

    filter_by_fund
    filter_additional_params
    refine_search

    Result.new(build_result_attributes)
  end

  private

  def initialize_query
    model_class = AggregatePortfolioInvestment
    model_class = model_class.with_snapshots if @params[:snapshot].present?
    @q = model_class.ransack(@params[:q])
  end

  def filter_by_fund
    return if @params[:fund_id].blank?

    if @params[:snapshot].present?
      snapshot_fund_ids = Fund.with_snapshots.where(orignal_id: @params[:fund_id]).pluck(:id)
      @aggregate_portfolio_investments = @aggregate_portfolio_investments.where(fund_id: snapshot_fund_ids)
    else
      @aggregate_portfolio_investments = @aggregate_portfolio_investments.where(fund_id: @params[:fund_id])
    end
  end

  def filter_additional_params
    # Handle aliasing of investor_id to portfolio_company_id
    portfolio_company_id = @params[:portfolio_company_id].presence || @params[:investor_id].presence

    @aggregate_portfolio_investments = @aggregate_portfolio_investments.where(portfolio_company_id: portfolio_company_id) if portfolio_company_id.present?
  end

  def refine_search
    @aggregate_portfolio_investments = AggregatePortfolioInvestmentSearch.perform(
      @aggregate_portfolio_investments,
      @current_user,
      @params
    )
  end

  def build_result_attributes
    result_attrs = {
      q: @q,
      aggregate_portfolio_investments: @aggregate_portfolio_investments,
      show_fund_name: @params["show_fund_name"] || false
    }

    build_time_series_result(result_attrs) if @params[:time_series].present?

    result_attrs
  end

  def build_time_series_result(result_attrs)
    fields = @params[:fields].presence || %i[fmv quantity gain]
    result_attrs[:time_series] = AggregatePortfolioInvestmentTimeSeries.new(@aggregate_portfolio_investments, fields).call
    result_attrs[:fields] = fields
  end
end
