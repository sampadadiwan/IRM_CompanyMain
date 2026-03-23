# Service for listing and filtering Portfolio Investments.
#
# This service encapsulates the logic for Ransack search (including snapshot handling),
# Pundit scoping, standard filters, search refinements, and view modes (DataFrame, Time Series).
#
# It ensures that a policy scope is always applied to the query:
# 1. If a block is given, it yields the relation to the block (allowing controllers to use `policy_scope` helper).
# 2. If no block is given, it uses `Pundit.policy_scope!` directly.
class PortfolioInvestmentList < BaseList
  Result = Struct.new(:q, :portfolio_investments, :data_frame, :adhoc_json, :template, :time_series, :fields, keyword_init: true)

  def call(&)
    initialize_query
    @portfolio_investments = apply_policy_scope(@q.result, &)
    @portfolio_investments = @portfolio_investments.include_proforma
                                                   .joins(:investment_instrument)
                                                   .includes(:aggregate_portfolio_investment, :fund, :investment_instrument, :portfolio_company, :valuation)

    filter_by_fund
    filter_by_fund_ids
    filter_by_portfolio_company_ids
    @portfolio_investments = filter_params(
      @portfolio_investments,
      :portfolio_company_id,
      :import_upload_id,
      :investment_instrument_id,
      :aggregate_portfolio_investment_id,
      :capital_distribution_id
    )
    @portfolio_investments = PortfolioInvestmentSearch.perform(@portfolio_investments, @current_user, @params)

    Result.new(build_result_attributes)
  end

  private

  def filter_by_portfolio_company_ids
    return if @params[:portfolio_company_ids].blank?

    portfolio_company_ids = @params[:portfolio_company_ids]

    @portfolio_investments = @portfolio_investments.where(portfolio_company_id: portfolio_company_ids).includes(:portfolio_company)
  end

  def initialize_query
    model_class = PortfolioInvestment
    model_class = model_class.with_snapshots if @params[:snapshot].present?

    @q = model_class.ransack(@params[:q])
  end

  def filter_by_fund
    return if @params[:fund_id].blank?

    if @params[:snapshot].present?
      snapshot_fund_ids = Fund.with_snapshots.where(orignal_id: @params[:fund_id]).pluck(:id)
      @portfolio_investments = @portfolio_investments.where(fund_id: snapshot_fund_ids)
    else
      @portfolio_investments = @portfolio_investments.where(fund_id: @params[:fund_id])
    end
  end

  def filter_by_fund_ids
    return if @params[:fund_ids].blank?

    @portfolio_investments = @portfolio_investments.where(fund_id: @params[:fund_ids])
  end

  def build_result_attributes
    result_attrs = { q: @q, portfolio_investments: @portfolio_investments }
    template = "index"

    if @params[:group_fields].present?
      build_data_frame_result(result_attrs)
      result_attrs[:template] = @params[:template].presence || template
    elsif @params[:time_series].present?
      build_time_series_result(result_attrs)
    end

    result_attrs[:template] ||= template
    result_attrs
  end

  def build_data_frame_result(result_attrs)
    @data_frame = PortfolioInvestmentDf.new.df(@portfolio_investments, @current_user, @params)
    result_attrs[:data_frame] = @data_frame
    result_attrs[:adhoc_json] = @data_frame.to_a.to_json
  end

  def build_time_series_result(result_attrs)
    fields = @params[:fields].presence || %i[fmv quantity gain]
    result_attrs[:time_series] = PortfolioInvestmentTimeSeries.new(@portfolio_investments, fields).call
    result_attrs[:fields] = fields
  end
end
