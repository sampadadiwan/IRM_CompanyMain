require "application_system_test_case"

class ScenarioInvestmentsTest < ApplicationSystemTestCase
  setup do
    @scenario_investment = scenario_investments(:one)
  end

  test "visiting the index" do
    visit scenario_investments_url
    assert_selector "h1", text: "Scenario investments"
  end

  test "should create scenario investment" do
    visit scenario_investments_url
    click_on "New scenario investment"

    fill_in "Entity", with: @scenario_investment.entity_id
    fill_in "Fund", with: @scenario_investment.fund_id
    fill_in "Notes", with: @scenario_investment.notes
    fill_in "Portfolio company", with: @scenario_investment.portfolio_company_id
    fill_in "Portfolio scenario", with: @scenario_investment.portfolio_scenario_id
    fill_in "Price", with: @scenario_investment.price
    fill_in "Quantity", with: @scenario_investment.quantity
    fill_in "Transaction date", with: @scenario_investment.transaction_date
    fill_in "User", with: @scenario_investment.user_id
    click_on "Create Scenario investment"

    assert_text "Scenario investment was successfully created"
    click_on "Back"
  end

  test "should update Scenario investment" do
    visit scenario_investment_url(@scenario_investment)
    click_on "Edit this scenario investment", match: :first

    fill_in "Entity", with: @scenario_investment.entity_id
    fill_in "Fund", with: @scenario_investment.fund_id
    fill_in "Notes", with: @scenario_investment.notes
    fill_in "Portfolio company", with: @scenario_investment.portfolio_company_id
    fill_in "Portfolio scenario", with: @scenario_investment.portfolio_scenario_id
    fill_in "Price", with: @scenario_investment.price
    fill_in "Quantity", with: @scenario_investment.quantity
    fill_in "Transaction date", with: @scenario_investment.transaction_date
    fill_in "User", with: @scenario_investment.user_id
    click_on "Update Scenario investment"

    assert_text "Scenario investment was successfully updated"
    click_on "Back"
  end

  test "should destroy Scenario investment" do
    visit scenario_investment_url(@scenario_investment)
    click_on "Destroy this scenario investment", match: :first

    assert_text "Scenario investment was successfully destroyed"
  end
end
