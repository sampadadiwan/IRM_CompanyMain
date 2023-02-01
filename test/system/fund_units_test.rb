require "application_system_test_case"

class FundUnitsTest < ApplicationSystemTestCase
  setup do
    @fund_unit = fund_units(:one)
  end

  test "visiting the index" do
    visit fund_units_url
    assert_selector "h1", text: "Fund units"
  end

  test "should create fund unit" do
    visit fund_units_url
    click_on "New fund unit"

    fill_in "Capital commitment", with: @fund_unit.capital_commitment_id
    fill_in "Fund", with: @fund_unit.fund_id
    fill_in "Investor", with: @fund_unit.investor_id
    fill_in "Quantity", with: @fund_unit.quantity
    fill_in "Reason", with: @fund_unit.reason
    fill_in "Unit type", with: @fund_unit.unit_type
    click_on "Create Fund unit"

    assert_text "Fund unit was successfully created"
    click_on "Back"
  end

  test "should update Fund unit" do
    visit fund_unit_url(@fund_unit)
    click_on "Edit this fund unit", match: :first

    fill_in "Capital commitment", with: @fund_unit.capital_commitment_id
    fill_in "Fund", with: @fund_unit.fund_id
    fill_in "Investor", with: @fund_unit.investor_id
    fill_in "Quantity", with: @fund_unit.quantity
    fill_in "Reason", with: @fund_unit.reason
    fill_in "Unit type", with: @fund_unit.unit_type
    click_on "Update Fund unit"

    assert_text "Fund unit was successfully updated"
    click_on "Back"
  end

  test "should destroy Fund unit" do
    visit fund_unit_url(@fund_unit)
    click_on "Destroy this fund unit", match: :first

    assert_text "Fund unit was successfully destroyed"
  end
end
