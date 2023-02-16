require "application_system_test_case"

class AggregatePortfolioInvestmentsTest < ApplicationSystemTestCase
  setup do
    @aggregate_portfolio_investment = aggregate_portfolio_investments(:one)
  end

  test "visiting the index" do
    visit aggregate_portfolio_investments_url
    assert_selector "h1", text: "Aggregate portfolio investments"
  end

  test "should create aggregate portfolio investment" do
    visit aggregate_portfolio_investments_url
    click_on "New aggregate portfolio investment"

    fill_in "Avg cost", with: @aggregate_portfolio_investment.avg_cost
    fill_in "Entity", with: @aggregate_portfolio_investment.entity_id
    fill_in "Fmv", with: @aggregate_portfolio_investment.fmv
    fill_in "Fund", with: @aggregate_portfolio_investment.fund_id
    fill_in "Portfolio company", with: @aggregate_portfolio_investment.portfolio_company_id
    fill_in "Portfolio company type", with: @aggregate_portfolio_investment.portfolio_company_type
    fill_in "Quantity", with: @aggregate_portfolio_investment.quantity
    click_on "Create Aggregate portfolio investment"

    assert_text "Aggregate portfolio investment was successfully created"
    click_on "Back"
  end

  test "should update Aggregate portfolio investment" do
    visit aggregate_portfolio_investment_url(@aggregate_portfolio_investment)
    click_on "Edit this aggregate portfolio investment", match: :first

    fill_in "Avg cost", with: @aggregate_portfolio_investment.avg_cost
    fill_in "Entity", with: @aggregate_portfolio_investment.entity_id
    fill_in "Fmv", with: @aggregate_portfolio_investment.fmv
    fill_in "Fund", with: @aggregate_portfolio_investment.fund_id
    fill_in "Portfolio company", with: @aggregate_portfolio_investment.portfolio_company_id
    fill_in "Portfolio company type", with: @aggregate_portfolio_investment.portfolio_company_type
    fill_in "Quantity", with: @aggregate_portfolio_investment.quantity
    click_on "Update Aggregate portfolio investment"

    assert_text "Aggregate portfolio investment was successfully updated"
    click_on "Back"
  end

  test "should destroy Aggregate portfolio investment" do
    visit aggregate_portfolio_investment_url(@aggregate_portfolio_investment)
    click_on "Destroy this aggregate portfolio investment", match: :first

    assert_text "Aggregate portfolio investment was successfully destroyed"
  end
end
