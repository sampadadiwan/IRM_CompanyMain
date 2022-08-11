require "application_system_test_case"

class InvestmentSnapshotsTest < ApplicationSystemTestCase
  setup do
    @investment_snapshot = investment_snapshots(:one)
  end

  test "visiting the index" do
    visit investment_snapshots_url
    assert_selector "h1", text: "Investment snapshots"
  end

  test "should create investment snapshot" do
    visit investment_snapshots_url
    click_on "New investment snapshot"

    # fill_in "Amount cents", with: @investment_snapshot.amount_cents
    # fill_in "Anti dilution", with: @investment_snapshot.anti_dilution
    # fill_in "As of", with: @investment_snapshot.as_of
    # fill_in "Category", with: @investment_snapshot.category
    # fill_in "Currency", with: @investment_snapshot.currency
    # fill_in "Current value", with: @investment_snapshot.current_value
    # fill_in "Deleted at", with: @investment_snapshot.deleted_at
    # fill_in "Diluted percentage", with: @investment_snapshot.diluted_percentage
    # fill_in "Diluted quantity", with: @investment_snapshot.diluted_quantity
    # check "Employee holdings" if @investment_snapshot.employee_holdings
    # fill_in "Entity", with: @investment_snapshot.entity_id
    # fill_in "Funding round", with: @investment_snapshot.funding_round_id
    # fill_in "Initial value", with: @investment_snapshot.initial_value
    # fill_in "Investment date", with: @investment_snapshot.investment_date
    # fill_in "Investment", with: @investment_snapshot.investment_id
    # fill_in "Investment instrument", with: @investment_snapshot.investment_instrument
    # fill_in "Investment type", with: @investment_snapshot.investment_type
    # fill_in "Investor", with: @investment_snapshot.investor_id
    # fill_in "Investor type", with: @investment_snapshot.investor_type
    # fill_in "Liq pref type", with: @investment_snapshot.liq_pref_type
    # fill_in "Liquidation preference", with: @investment_snapshot.liquidation_preference
    # fill_in "Percentage holding", with: @investment_snapshot.percentage_holding
    # fill_in "Price cents", with: @investment_snapshot.price_cents
    # fill_in "Quantity", with: @investment_snapshot.quantity
    # fill_in "Spv", with: @investment_snapshot.spv
    # fill_in "Status", with: @investment_snapshot.status
    # fill_in "Tag", with: @investment_snapshot.tag
    # fill_in "Units", with: @investment_snapshot.units
    click_on "Create Investment snapshot"

    assert_text "Investment snapshot was successfully created"
    click_on "Back"
  end

  test "should update Investment snapshot" do
    visit investment_snapshot_url(@investment_snapshot)
    click_on "Edit this investment snapshot", match: :first

    # fill_in "Amount cents", with: @investment_snapshot.amount_cents
    # fill_in "Anti dilution", with: @investment_snapshot.anti_dilution
    # fill_in "As of", with: @investment_snapshot.as_of
    # fill_in "Category", with: @investment_snapshot.category
    # fill_in "Currency", with: @investment_snapshot.currency
    # fill_in "Current value", with: @investment_snapshot.current_value
    # fill_in "Deleted at", with: @investment_snapshot.deleted_at
    # fill_in "Diluted percentage", with: @investment_snapshot.diluted_percentage
    # fill_in "Diluted quantity", with: @investment_snapshot.diluted_quantity
    # check "Employee holdings" if @investment_snapshot.employee_holdings
    # fill_in "Entity", with: @investment_snapshot.entity_id
    # fill_in "Funding round", with: @investment_snapshot.funding_round_id
    # fill_in "Initial value", with: @investment_snapshot.initial_value
    # fill_in "Investment date", with: @investment_snapshot.investment_date
    # fill_in "Investment", with: @investment_snapshot.investment_id
    # fill_in "Investment instrument", with: @investment_snapshot.investment_instrument
    # fill_in "Investment type", with: @investment_snapshot.investment_type
    # fill_in "Investor", with: @investment_snapshot.investor_id
    # fill_in "Investor type", with: @investment_snapshot.investor_type
    # fill_in "Liq pref type", with: @investment_snapshot.liq_pref_type
    # fill_in "Liquidation preference", with: @investment_snapshot.liquidation_preference
    # fill_in "Percentage holding", with: @investment_snapshot.percentage_holding
    # fill_in "Price cents", with: @investment_snapshot.price_cents
    # fill_in "Quantity", with: @investment_snapshot.quantity
    # fill_in "Spv", with: @investment_snapshot.spv
    # fill_in "Status", with: @investment_snapshot.status
    # fill_in "Tag", with: @investment_snapshot.tag
    # fill_in "Units", with: @investment_snapshot.units
    click_on "Update Investment snapshot"

    assert_text "Investment snapshot was successfully updated"
    click_on "Back"
  end

  test "should destroy Investment snapshot" do
    visit investment_snapshot_url(@investment_snapshot)
    click_on "Destroy this investment snapshot", match: :first

    assert_text "Investment snapshot was successfully destroyed"
  end
end
