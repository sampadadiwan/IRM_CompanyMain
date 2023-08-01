require "application_system_test_case"

class PortfolioScenariosTest < ApplicationSystemTestCase
  setup do
    @portfolio_scenario = portfolio_scenarios(:one)
  end

  test "visiting the index" do
    visit portfolio_scenarios_url
    assert_selector "h1", text: "Portfolio scenarios"
  end

  test "should create portfolio scenario" do
    visit portfolio_scenarios_url
    click_on "New portfolio scenario"

    fill_in "Entity", with: @portfolio_scenario.entity_id
    fill_in "Fund", with: @portfolio_scenario.fund_id
    fill_in "Name", with: @portfolio_scenario.name
    fill_in "User", with: @portfolio_scenario.user_id
    click_on "Create Portfolio scenario"

    assert_text "Portfolio scenario was successfully created"
    click_on "Back"
  end

  test "should update Portfolio scenario" do
    visit portfolio_scenario_url(@portfolio_scenario)
    click_on "Edit this portfolio scenario", match: :first

    fill_in "Entity", with: @portfolio_scenario.entity_id
    fill_in "Fund", with: @portfolio_scenario.fund_id
    fill_in "Name", with: @portfolio_scenario.name
    fill_in "User", with: @portfolio_scenario.user_id
    click_on "Update Portfolio scenario"

    assert_text "Portfolio scenario was successfully updated"
    click_on "Back"
  end

  test "should destroy Portfolio scenario" do
    visit portfolio_scenario_url(@portfolio_scenario)
    click_on "Destroy this portfolio scenario", match: :first

    assert_text "Portfolio scenario was successfully destroyed"
  end
end
