require "application_system_test_case"

class ExcusedInvestorsTest < ApplicationSystemTestCase
  setup do
    @excused_investor = excused_investors(:one)
  end

  test "visiting the index" do
    visit excused_investors_url
    assert_selector "h1", text: "Excused investors"
  end

  test "should create excused investor" do
    visit excused_investors_url
    click_on "New excused investor"

    fill_in "Aggregate portfolio investment", with: @excused_investor.aggregate_portfolio_investment_id
    fill_in "Entity", with: @excused_investor.entity_id
    fill_in "Folio", with: @excused_investor.folio_id
    fill_in "Fund", with: @excused_investor.fund_id
    fill_in "Notes", with: @excused_investor.notes
    fill_in "Portfolio company", with: @excused_investor.portfolio_company_id
    fill_in "Portfolio investment", with: @excused_investor.portfolio_investment_id
    click_on "Create Excused investor"

    assert_text "Excused investor was successfully created"
    click_on "Back"
  end

  test "should update Excused investor" do
    visit excused_investor_url(@excused_investor)
    click_on "Edit this excused investor", match: :first

    fill_in "Aggregate portfolio investment", with: @excused_investor.aggregate_portfolio_investment_id
    fill_in "Entity", with: @excused_investor.entity_id
    fill_in "Folio", with: @excused_investor.folio_id
    fill_in "Fund", with: @excused_investor.fund_id
    fill_in "Notes", with: @excused_investor.notes
    fill_in "Portfolio company", with: @excused_investor.portfolio_company_id
    fill_in "Portfolio investment", with: @excused_investor.portfolio_investment_id
    click_on "Update Excused investor"

    assert_text "Excused investor was successfully updated"
    click_on "Back"
  end

  test "should destroy Excused investor" do
    visit excused_investor_url(@excused_investor)
    click_on "Destroy this excused investor", match: :first

    assert_text "Excused investor was successfully destroyed"
  end
end
