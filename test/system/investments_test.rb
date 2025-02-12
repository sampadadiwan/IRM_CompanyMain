require "application_system_test_case"

class InvestmentsTest < ApplicationSystemTestCase
  setup do
    @investment = investments(:one)
  end

  test "visiting the index" do
    visit investments_url
    assert_selector "h1", text: "Investments"
  end

  test "should create investment" do
    visit investments_url
    click_on "New investment"

    fill_in "Amount cents", with: @investment.amount_cents
    fill_in "Category", with: @investment.category
    fill_in "Funding round", with: @investment.funding_round
    fill_in "Investment date", with: @investment.investment_date
    fill_in "Investment type", with: @investment.investment_type
    fill_in "Investor name", with: @investment.investor_name
    fill_in "Notes", with: @investment.notes
    fill_in "Portfolio company", with: @investment.portfolio_company_id
    fill_in "Price cents", with: @investment.price_cents
    fill_in "Quantity", with: @investment.quantity
    click_on "Create Investment"

    assert_text "Investment was successfully created"
    click_on "Back"
  end

  test "should update Investment" do
    visit investment_url(@investment)
    click_on "Edit this investment", match: :first

    fill_in "Amount cents", with: @investment.amount_cents
    fill_in "Category", with: @investment.category
    fill_in "Funding round", with: @investment.funding_round
    fill_in "Investment date", with: @investment.investment_date
    fill_in "Investment type", with: @investment.investment_type
    fill_in "Investor name", with: @investment.investor_name
    fill_in "Notes", with: @investment.notes
    fill_in "Portfolio company", with: @investment.portfolio_company_id
    fill_in "Price cents", with: @investment.price_cents
    fill_in "Quantity", with: @investment.quantity
    click_on "Update Investment"

    assert_text "Investment was successfully updated"
    click_on "Back"
  end

  test "should destroy Investment" do
    visit investment_url(@investment)
    click_on "Destroy this investment", match: :first

    assert_text "Investment was successfully destroyed"
  end
end
