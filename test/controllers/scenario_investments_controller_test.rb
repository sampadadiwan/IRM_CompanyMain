require "test_helper"

class ScenarioInvestmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @scenario_investment = scenario_investments(:one)
  end

  test "should get index" do
    get scenario_investments_url
    assert_response :success
  end

  test "should get new" do
    get new_scenario_investment_url
    assert_response :success
  end

  test "should create scenario_investment" do
    assert_difference("ScenarioInvestment.count") do
      post scenario_investments_url, params: { scenario_investment: { entity_id: @scenario_investment.entity_id, fund_id: @scenario_investment.fund_id, notes: @scenario_investment.notes, portfolio_company_id: @scenario_investment.portfolio_company_id, portfolio_scenario_id: @scenario_investment.portfolio_scenario_id, price: @scenario_investment.price, quantity: @scenario_investment.quantity, transaction_date: @scenario_investment.transaction_date, user_id: @scenario_investment.user_id } }
    end

    assert_redirected_to scenario_investment_url(ScenarioInvestment.last)
  end

  test "should show scenario_investment" do
    get scenario_investment_url(@scenario_investment)
    assert_response :success
  end

  test "should get edit" do
    get edit_scenario_investment_url(@scenario_investment)
    assert_response :success
  end

  test "should update scenario_investment" do
    patch scenario_investment_url(@scenario_investment), params: { scenario_investment: { entity_id: @scenario_investment.entity_id, fund_id: @scenario_investment.fund_id, notes: @scenario_investment.notes, portfolio_company_id: @scenario_investment.portfolio_company_id, portfolio_scenario_id: @scenario_investment.portfolio_scenario_id, price: @scenario_investment.price, quantity: @scenario_investment.quantity, transaction_date: @scenario_investment.transaction_date, user_id: @scenario_investment.user_id } }
    assert_redirected_to scenario_investment_url(@scenario_investment)
  end

  test "should destroy scenario_investment" do
    assert_difference("ScenarioInvestment.count", -1) do
      delete scenario_investment_url(@scenario_investment)
    end

    assert_redirected_to scenario_investments_url
  end
end
