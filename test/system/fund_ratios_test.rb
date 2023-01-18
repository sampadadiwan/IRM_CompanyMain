require "application_system_test_case"

class FundRatiosTest < ApplicationSystemTestCase
  setup do
    @fund_ratio = fund_ratios(:one)
  end

  test "visiting the index" do
    visit fund_ratios_url
    assert_selector "h1", text: "Fund ratios"
  end

  test "should create fund ratio" do
    visit fund_ratios_url
    click_on "New fund ratio"

    fill_in "Display value", with: @fund_ratio.display_value
    fill_in "Entity", with: @fund_ratio.entity_id
    fill_in "Fund", with: @fund_ratio.fund_id
    fill_in "Name", with: @fund_ratio.name
    fill_in "Notes", with: @fund_ratio.notes
    fill_in "Valuation", with: @fund_ratio.valuation_id
    fill_in "Value", with: @fund_ratio.value
    click_on "Create Fund ratio"

    assert_text "Fund ratio was successfully created"
    click_on "Back"
  end

  test "should update Fund ratio" do
    visit fund_ratio_url(@fund_ratio)
    click_on "Edit this fund ratio", match: :first

    fill_in "Display value", with: @fund_ratio.display_value
    fill_in "Entity", with: @fund_ratio.entity_id
    fill_in "Fund", with: @fund_ratio.fund_id
    fill_in "Name", with: @fund_ratio.name
    fill_in "Notes", with: @fund_ratio.notes
    fill_in "Valuation", with: @fund_ratio.valuation_id
    fill_in "Value", with: @fund_ratio.value
    click_on "Update Fund ratio"

    assert_text "Fund ratio was successfully updated"
    click_on "Back"
  end

  test "should destroy Fund ratio" do
    visit fund_ratio_url(@fund_ratio)
    click_on "Destroy this fund ratio", match: :first

    assert_text "Fund ratio was successfully destroyed"
  end
end
