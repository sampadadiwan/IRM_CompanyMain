require "application_system_test_case"

class CapitalRemittancesTest < ApplicationSystemTestCase
  setup do
    @capital_remittance = capital_remittances(:one)
  end

  test "visiting the index" do
    visit capital_remittances_url
    assert_selector "h1", text: "Capital remittances"
  end

  test "should create capital remittance" do
    visit capital_remittances_url
    click_on "New capital remittance"

    fill_in "Capital call", with: @capital_remittance.capital_call_id
    fill_in "Collected amount", with: @capital_remittance.collected_amount
    fill_in "Due amount", with: @capital_remittance.due_amount
    fill_in "Entity", with: @capital_remittance.entity_id
    fill_in "Fund", with: @capital_remittance.fund_id
    fill_in "Investor", with: @capital_remittance.investor_id
    fill_in "Notes", with: @capital_remittance.notes
    fill_in "Status", with: @capital_remittance.status
    click_on "Create Capital remittance"

    assert_text "Capital remittance was successfully created"
    click_on "Back"
  end

  test "should update Capital remittance" do
    visit capital_remittance_url(@capital_remittance)
    click_on "Edit this capital remittance", match: :first

    fill_in "Capital call", with: @capital_remittance.capital_call_id
    fill_in "Collected amount", with: @capital_remittance.collected_amount
    fill_in "Due amount", with: @capital_remittance.due_amount
    fill_in "Entity", with: @capital_remittance.entity_id
    fill_in "Fund", with: @capital_remittance.fund_id
    fill_in "Investor", with: @capital_remittance.investor_id
    fill_in "Notes", with: @capital_remittance.notes
    fill_in "Status", with: @capital_remittance.status
    click_on "Update Capital remittance"

    assert_text "Capital remittance was successfully updated"
    click_on "Back"
  end

  test "should destroy Capital remittance" do
    visit capital_remittance_url(@capital_remittance)
    click_on "Destroy this capital remittance", match: :first

    assert_text "Capital remittance was successfully destroyed"
  end
end
