require "application_system_test_case"

class StockAdjustmentsTest < ApplicationSystemTestCase
  setup do
    @stock_adjustment = stock_adjustments(:one)
  end

  test "visiting the index" do
    visit stock_adjustments_url
    assert_selector "h1", text: "Stock adjustments"
  end

  test "should create stock adjustment" do
    visit stock_adjustments_url
    click_on "New stock adjustment"

    fill_in "Adjustment", with: @stock_adjustment.adjustment
    fill_in "Entity", with: @stock_adjustment.entity_id
    fill_in "Notes", with: @stock_adjustment.notes
    fill_in "Portfolio company", with: @stock_adjustment.portfolio_company_id
    fill_in "User", with: @stock_adjustment.user_id
    click_on "Create Stock adjustment"

    assert_text "Stock adjustment was successfully created"
    click_on "Back"
  end

  test "should update Stock adjustment" do
    visit stock_adjustment_url(@stock_adjustment)
    click_on "Edit this stock adjustment", match: :first

    fill_in "Adjustment", with: @stock_adjustment.adjustment
    fill_in "Entity", with: @stock_adjustment.entity_id
    fill_in "Notes", with: @stock_adjustment.notes
    fill_in "Portfolio company", with: @stock_adjustment.portfolio_company_id
    fill_in "User", with: @stock_adjustment.user_id
    click_on "Update Stock adjustment"

    assert_text "Stock adjustment was successfully updated"
    click_on "Back"
  end

  test "should destroy Stock adjustment" do
    visit stock_adjustment_url(@stock_adjustment)
    click_on "Destroy this stock adjustment", match: :first

    assert_text "Stock adjustment was successfully destroyed"
  end
end
