require "application_system_test_case"

class InvestorNoticeEntriesTest < ApplicationSystemTestCase
  setup do
    @investor_notice_entry = investor_notice_entries(:one)
  end

  test "visiting the index" do
    visit investor_notice_entries_url
    assert_selector "h1", text: "Investor notice entries"
  end

  test "should create investor notice entry" do
    visit investor_notice_entries_url
    click_on "New investor notice entry"

    check "Active" if @investor_notice_entry.active
    fill_in "Entity", with: @investor_notice_entry.entity_id
    fill_in "Investor entity id", with: @investor_notice_entry.investor_entity_id_id
    fill_in "Investor", with: @investor_notice_entry.investor_id
    fill_in "Investor notice", with: @investor_notice_entry.investor_notice_id
    click_on "Create Investor notice entry"

    assert_text "Investor notice entry was successfully created"
    click_on "Back"
  end

  test "should update Investor notice entry" do
    visit investor_notice_entry_url(@investor_notice_entry)
    click_on "Edit this investor notice entry", match: :first

    check "Active" if @investor_notice_entry.active
    fill_in "Entity", with: @investor_notice_entry.entity_id
    fill_in "Investor entity id", with: @investor_notice_entry.investor_entity_id_id
    fill_in "Investor", with: @investor_notice_entry.investor_id
    fill_in "Investor notice", with: @investor_notice_entry.investor_notice_id
    click_on "Update Investor notice entry"

    assert_text "Investor notice entry was successfully updated"
    click_on "Back"
  end

  test "should destroy Investor notice entry" do
    visit investor_notice_entry_url(@investor_notice_entry)
    click_on "Destroy this investor notice entry", match: :first

    assert_text "Investor notice entry was successfully destroyed"
  end
end
