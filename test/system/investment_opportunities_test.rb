require "application_system_test_case"

class InvestmentOpportunitiesTest < ApplicationSystemTestCase
  setup do
    @investment_opportunity = investment_opportunities(:one)
  end

  test "visiting the index" do
    visit investment_opportunities_url
    assert_selector "h1", text: "Investment opportunities"
  end

  test "should create investment opportunity" do
    visit investment_opportunities_url
    click_on "New investment opportunity"

    fill_in "Company name", with: @investment_opportunity.company_name
    fill_in "Currency", with: @investment_opportunity.currency
    fill_in "Entity", with: @investment_opportunity.entity_id
    fill_in "Fund raise amount", with: @investment_opportunity.fund_raise_amount
    fill_in "Last date", with: @investment_opportunity.last_date
    fill_in "Min ticket size", with: @investment_opportunity.min_ticket_size
    fill_in "Valuation", with: @investment_opportunity.valuation
    click_on "Create Investment opportunity"

    assert_text "Investment opportunity was successfully created"
    click_on "Back"
  end

  test "should update Investment opportunity" do
    visit investment_opportunity_url(@investment_opportunity)
    click_on "Edit this investment opportunity", match: :first

    fill_in "Company name", with: @investment_opportunity.company_name
    fill_in "Currency", with: @investment_opportunity.currency
    fill_in "Entity", with: @investment_opportunity.entity_id
    fill_in "Fund raise amount", with: @investment_opportunity.fund_raise_amount
    fill_in "Last date", with: @investment_opportunity.last_date
    fill_in "Min ticket size", with: @investment_opportunity.min_ticket_size
    fill_in "Valuation", with: @investment_opportunity.valuation
    click_on "Update Investment opportunity"

    assert_text "Investment opportunity was successfully updated"
    click_on "Back"
  end

  test "should destroy Investment opportunity" do
    visit investment_opportunity_url(@investment_opportunity)
    click_on "Destroy this investment opportunity", match: :first

    assert_text "Investment opportunity was successfully destroyed"
  end
end
