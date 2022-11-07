require "application_system_test_case"

class InvestorNoticesTest < ApplicationSystemTestCase
  setup do
    @investor_notice = investor_notices(:one)
  end

  test "visiting the index" do
    visit investor_notices_url
    assert_selector "h1", text: "Investor notices"
  end

  test "should create investor notice" do
    visit investor_notices_url
    click_on "New investor notice"

    check "Active" if @investor_notice.active
    fill_in "End date", with: @investor_notice.end_date
    fill_in "Entity", with: @investor_notice.entity_id
    fill_in "Investor entity id", with: @investor_notice.investor_entity_id_id
    fill_in "Investor", with: @investor_notice.investor_id
    fill_in "Start date", with: @investor_notice.start_date
    click_on "Create Investor notice"

    assert_text "Investor notice was successfully created"
    click_on "Back"
  end

  test "should update Investor notice" do
    visit investor_notice_url(@investor_notice)
    click_on "Edit this investor notice", match: :first

    check "Active" if @investor_notice.active
    fill_in "End date", with: @investor_notice.end_date
    fill_in "Entity", with: @investor_notice.entity_id
    fill_in "Investor entity id", with: @investor_notice.investor_entity_id_id
    fill_in "Investor", with: @investor_notice.investor_id
    fill_in "Start date", with: @investor_notice.start_date
    click_on "Update Investor notice"

    assert_text "Investor notice was successfully updated"
    click_on "Back"
  end

  test "should destroy Investor notice" do
    visit investor_notice_url(@investor_notice)
    click_on "Destroy this investor notice", match: :first

    assert_text "Investor notice was successfully destroyed"
  end
end
