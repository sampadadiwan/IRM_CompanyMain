require "application_system_test_case"

class PortfolioCashflowsTest < ApplicationSystemTestCase
  setup do
    @portfolio_cashflow = portfolio_cashflows(:one)
  end

  test "visiting the index" do
    visit portfolio_cashflows_url
    assert_selector "h1", text: "Portfolio cashflows"
  end

  test "should create portfolio cashflow" do
    visit portfolio_cashflows_url
    click_on "New portfolio cashflow"

    fill_in "Aggregate portfolio investment", with: @portfolio_cashflow.aggregate_portfolio_investment_id
    fill_in "Amount", with: @portfolio_cashflow.amount
    fill_in "Entity", with: @portfolio_cashflow.entity_id
    fill_in "Fund", with: @portfolio_cashflow.fund_id
    fill_in "Notes", with: @portfolio_cashflow.notes
    fill_in "Payment date", with: @portfolio_cashflow.payment_date
    fill_in "Portfolio company", with: @portfolio_cashflow.portfolio_company_id
    click_on "Create Portfolio cashflow"

    assert_text "Portfolio cashflow was successfully created"
    click_on "Back"
  end

  test "should update Portfolio cashflow" do
    visit portfolio_cashflow_url(@portfolio_cashflow)
    click_on "Edit this portfolio cashflow", match: :first

    fill_in "Aggregate portfolio investment", with: @portfolio_cashflow.aggregate_portfolio_investment_id
    fill_in "Amount", with: @portfolio_cashflow.amount
    fill_in "Entity", with: @portfolio_cashflow.entity_id
    fill_in "Fund", with: @portfolio_cashflow.fund_id
    fill_in "Notes", with: @portfolio_cashflow.notes
    fill_in "Payment date", with: @portfolio_cashflow.payment_date
    fill_in "Portfolio company", with: @portfolio_cashflow.portfolio_company_id
    click_on "Update Portfolio cashflow"

    assert_text "Portfolio cashflow was successfully updated"
    click_on "Back"
  end

  test "should destroy Portfolio cashflow" do
    visit portfolio_cashflow_url(@portfolio_cashflow)
    click_on "Destroy this portfolio cashflow", match: :first

    assert_text "Portfolio cashflow was successfully destroyed"
  end
end
