require "test_helper"

class PortfolioInvestmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @portfolio_investment = portfolio_investments(:one)
  end

  test "should get index" do
    get portfolio_investments_url
    assert_response :success
  end

  test "should get new" do
    get new_portfolio_investment_url
    assert_response :success
  end

  test "should create portfolio_investment" do
    assert_difference("PortfolioInvestment.count") do
      post portfolio_investments_url, params: { portfolio_investment: { amount: @portfolio_investment.amount, company_name: @portfolio_investment.company_name, entity_id: @portfolio_investment.entity_id, fund_id: @portfolio_investment.fund_id, investment_date: @portfolio_investment.investment_date, investment_type: @portfolio_investment.investment_type, notes: @portfolio_investment.notes, quantity: @portfolio_investment.quantity } }
    end

    assert_redirected_to portfolio_investment_url(PortfolioInvestment.last)
  end

  test "should show portfolio_investment" do
    get portfolio_investment_url(@portfolio_investment)
    assert_response :success
  end

  test "should get edit" do
    get edit_portfolio_investment_url(@portfolio_investment)
    assert_response :success
  end

  test "should update portfolio_investment" do
    patch portfolio_investment_url(@portfolio_investment), params: { portfolio_investment: { amount: @portfolio_investment.amount, company_name: @portfolio_investment.company_name, entity_id: @portfolio_investment.entity_id, fund_id: @portfolio_investment.fund_id, investment_date: @portfolio_investment.investment_date, investment_type: @portfolio_investment.investment_type, notes: @portfolio_investment.notes, quantity: @portfolio_investment.quantity } }
    assert_redirected_to portfolio_investment_url(@portfolio_investment)
  end

  test "should destroy portfolio_investment" do
    assert_difference("PortfolioInvestment.count", -1) do
      delete portfolio_investment_url(@portfolio_investment)
    end

    assert_redirected_to portfolio_investments_url
  end
end
