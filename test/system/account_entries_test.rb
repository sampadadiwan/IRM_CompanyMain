require "application_system_test_case"

class AccountEntriesTest < ApplicationSystemTestCase
  setup do
    @account_entry = account_entries(:one)
  end

  test "visiting the index" do
    visit account_entries_url
    assert_selector "h1", text: "Account entries"
  end

  test "should create account entry" do
    visit account_entries_url
    click_on "New account entry"

    fill_in "Amount", with: @account_entry.amount
    fill_in "Capital commitment", with: @account_entry.capital_commitment_id
    fill_in "Entity", with: @account_entry.entity_id
    fill_in "Entry type", with: @account_entry.entry_type
    fill_in "Folio", with: @account_entry.folio_id
    fill_in "Fund", with: @account_entry.fund_id
    fill_in "Investor", with: @account_entry.investor_id
    fill_in "Name", with: @account_entry.name
    fill_in "Notes", with: @account_entry.notes
    fill_in "Reporting date", with: @account_entry.reporting_date
    click_on "Create Account entry"

    assert_text "Account entry was successfully created"
    click_on "Back"
  end

  test "should update Account entry" do
    visit account_entry_url(@account_entry)
    click_on "Edit this account entry", match: :first

    fill_in "Amount", with: @account_entry.amount
    fill_in "Capital commitment", with: @account_entry.capital_commitment_id
    fill_in "Entity", with: @account_entry.entity_id
    fill_in "Entry type", with: @account_entry.entry_type
    fill_in "Folio", with: @account_entry.folio_id
    fill_in "Fund", with: @account_entry.fund_id
    fill_in "Investor", with: @account_entry.investor_id
    fill_in "Name", with: @account_entry.name
    fill_in "Notes", with: @account_entry.notes
    fill_in "Reporting date", with: @account_entry.reporting_date
    click_on "Update Account entry"

    assert_text "Account entry was successfully updated"
    click_on "Back"
  end

  test "should destroy Account entry" do
    visit account_entry_url(@account_entry)
    click_on "Destroy this account entry", match: :first

    assert_text "Account entry was successfully destroyed"
  end
end
