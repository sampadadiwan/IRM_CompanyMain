require "test_helper"

class PortfolioScenariosControllerTest < ActionDispatch::IntegrationTest
  setup do
    @portfolio_scenario = portfolio_scenarios(:one)
  end

  test "should get index" do
    get portfolio_scenarios_url
    assert_response :success
  end

  test "should get new" do
    get new_portfolio_scenario_url
    assert_response :success
  end

  test "should create portfolio_scenario" do
    assert_difference("PortfolioScenario.count") do
      post portfolio_scenarios_url, params: { portfolio_scenario: { entity_id: @portfolio_scenario.entity_id, fund_id: @portfolio_scenario.fund_id, name: @portfolio_scenario.name, user_id: @portfolio_scenario.user_id } }
    end

    assert_redirected_to portfolio_scenario_url(PortfolioScenario.last)
  end

  test "should show portfolio_scenario" do
    get portfolio_scenario_url(@portfolio_scenario)
    assert_response :success
  end

  test "should get edit" do
    get edit_portfolio_scenario_url(@portfolio_scenario)
    assert_response :success
  end

  test "should update portfolio_scenario" do
    patch portfolio_scenario_url(@portfolio_scenario), params: { portfolio_scenario: { entity_id: @portfolio_scenario.entity_id, fund_id: @portfolio_scenario.fund_id, name: @portfolio_scenario.name, user_id: @portfolio_scenario.user_id } }
    assert_redirected_to portfolio_scenario_url(@portfolio_scenario)
  end

  test "should destroy portfolio_scenario" do
    assert_difference("PortfolioScenario.count", -1) do
      delete portfolio_scenario_url(@portfolio_scenario)
    end

    assert_redirected_to portfolio_scenarios_url
  end
end
