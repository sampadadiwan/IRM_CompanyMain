require "test_helper"

class AggregatePortfolioInvestmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @aggregate_portfolio_investment = aggregate_portfolio_investments(:one)
  end

  test "should get index" do
    get aggregate_portfolio_investments_url
    assert_response :success
  end

  test "should get new" do
    get new_aggregate_portfolio_investment_url
    assert_response :success
  end

  test "should create aggregate_portfolio_investment" do
    assert_difference("AggregatePortfolioInvestment.count") do
      post aggregate_portfolio_investments_url, params: { aggregate_portfolio_investment: { avg_cost: @aggregate_portfolio_investment.avg_cost, entity_id: @aggregate_portfolio_investment.entity_id, fmv: @aggregate_portfolio_investment.fmv, fund_id: @aggregate_portfolio_investment.fund_id, portfolio_company_id: @aggregate_portfolio_investment.portfolio_company_id, portfolio_company_type: @aggregate_portfolio_investment.portfolio_company_type, quantity: @aggregate_portfolio_investment.quantity } }
    end

    assert_redirected_to aggregate_portfolio_investment_url(AggregatePortfolioInvestment.last)
  end

  test "should show aggregate_portfolio_investment" do
    get aggregate_portfolio_investment_url(@aggregate_portfolio_investment)
    assert_response :success
  end

  test "should get edit" do
    get edit_aggregate_portfolio_investment_url(@aggregate_portfolio_investment)
    assert_response :success
  end

  test "should update aggregate_portfolio_investment" do
    patch aggregate_portfolio_investment_url(@aggregate_portfolio_investment), params: { aggregate_portfolio_investment: { avg_cost: @aggregate_portfolio_investment.avg_cost, entity_id: @aggregate_portfolio_investment.entity_id, fmv: @aggregate_portfolio_investment.fmv, fund_id: @aggregate_portfolio_investment.fund_id, portfolio_company_id: @aggregate_portfolio_investment.portfolio_company_id, portfolio_company_type: @aggregate_portfolio_investment.portfolio_company_type, quantity: @aggregate_portfolio_investment.quantity } }
    assert_redirected_to aggregate_portfolio_investment_url(@aggregate_portfolio_investment)
  end

  test "should destroy aggregate_portfolio_investment" do
    assert_difference("AggregatePortfolioInvestment.count", -1) do
      delete aggregate_portfolio_investment_url(@aggregate_portfolio_investment)
    end

    assert_redirected_to aggregate_portfolio_investments_url
  end
end
