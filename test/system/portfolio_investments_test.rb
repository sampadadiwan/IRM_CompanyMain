require "application_system_test_case"

class PortfolioInvestmentsTest < ApplicationSystemTestCase
  setup do
    @portfolio_investment = portfolio_investments(:one)
  end

  test "visiting the index" do
    visit portfolio_investments_url
    assert_selector "h1", text: "Portfolio investments"
  end

  test "should create portfolio investment" do
    visit portfolio_investments_url
    click_on "New portfolio investment"

    fill_in "Amount", with: @portfolio_investment.amount
    fill_in "Company name", with: @portfolio_investment.company_name
    fill_in "Entity", with: @portfolio_investment.entity_id
    fill_in "Fund", with: @portfolio_investment.fund_id
    fill_in "Investment date", with: @portfolio_investment.investment_date
    fill_in "Investment type", with: @portfolio_investment.investment_type
    fill_in "Notes", with: @portfolio_investment.notes
    fill_in "Quantity", with: @portfolio_investment.quantity
    click_on "Create Portfolio investment"

    assert_text "Portfolio investment was successfully created"
    click_on "Back"
  end

  test "should update Portfolio investment" do
    visit portfolio_investment_url(@portfolio_investment)
    click_on "Edit this portfolio investment", match: :first

    fill_in "Amount", with: @portfolio_investment.amount
    fill_in "Company name", with: @portfolio_investment.company_name
    fill_in "Entity", with: @portfolio_investment.entity_id
    fill_in "Fund", with: @portfolio_investment.fund_id
    fill_in "Investment date", with: @portfolio_investment.investment_date
    fill_in "Investment type", with: @portfolio_investment.investment_type
    fill_in "Notes", with: @portfolio_investment.notes
    fill_in "Quantity", with: @portfolio_investment.quantity
    click_on "Update Portfolio investment"

    assert_text "Portfolio investment was successfully updated"
    click_on "Back"
  end

  test "should destroy Portfolio investment" do
    visit portfolio_investment_url(@portfolio_investment)
    click_on "Destroy this portfolio investment", match: :first

    assert_text "Portfolio investment was successfully destroyed"
  end
end
