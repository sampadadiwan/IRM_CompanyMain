require "test_helper"

class PortfolioCashflowsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @portfolio_cashflow = portfolio_cashflows(:one)
  end

  test "should get index" do
    get portfolio_cashflows_url
    assert_response :success
  end

  test "should get new" do
    get new_portfolio_cashflow_url
    assert_response :success
  end

  test "should create portfolio_cashflow" do
    assert_difference("PortfolioCashflow.count") do
      post portfolio_cashflows_url, params: { portfolio_cashflow: { aggregate_portfolio_investment_id: @portfolio_cashflow.aggregate_portfolio_investment_id, amount: @portfolio_cashflow.amount, entity_id: @portfolio_cashflow.entity_id, fund_id: @portfolio_cashflow.fund_id, notes: @portfolio_cashflow.notes, payment_date: @portfolio_cashflow.payment_date, portfolio_company_id: @portfolio_cashflow.portfolio_company_id } }
    end

    assert_redirected_to portfolio_cashflow_url(PortfolioCashflow.last)
  end

  test "should show portfolio_cashflow" do
    get portfolio_cashflow_url(@portfolio_cashflow)
    assert_response :success
  end

  test "should get edit" do
    get edit_portfolio_cashflow_url(@portfolio_cashflow)
    assert_response :success
  end

  test "should update portfolio_cashflow" do
    patch portfolio_cashflow_url(@portfolio_cashflow), params: { portfolio_cashflow: { aggregate_portfolio_investment_id: @portfolio_cashflow.aggregate_portfolio_investment_id, amount: @portfolio_cashflow.amount, entity_id: @portfolio_cashflow.entity_id, fund_id: @portfolio_cashflow.fund_id, notes: @portfolio_cashflow.notes, payment_date: @portfolio_cashflow.payment_date, portfolio_company_id: @portfolio_cashflow.portfolio_company_id } }
    assert_redirected_to portfolio_cashflow_url(@portfolio_cashflow)
  end

  test "should destroy portfolio_cashflow" do
    assert_difference("PortfolioCashflow.count", -1) do
      delete portfolio_cashflow_url(@portfolio_cashflow)
    end

    assert_redirected_to portfolio_cashflows_url
  end
end
