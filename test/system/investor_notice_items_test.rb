require "application_system_test_case"

class InvestorNoticeItemsTest < ApplicationSystemTestCase
  setup do
    @investor_notice_item = investor_notice_items(:one)
  end

  test "visiting the index" do
    visit investor_notice_items_url
    assert_selector "h1", text: "Investor notice items"
  end

  test "should create investor notice item" do
    visit investor_notice_items_url
    click_on "New investor notice item"

    fill_in "Details", with: @investor_notice_item.details
    fill_in "Investor notice", with: @investor_notice_item.investor_notice_id
    fill_in "Link", with: @investor_notice_item.link
    fill_in "Title", with: @investor_notice_item.title
    click_on "Create Investor notice item"

    assert_text "Investor notice item was successfully created"
    click_on "Back"
  end

  test "should update Investor notice item" do
    visit investor_notice_item_url(@investor_notice_item)
    click_on "Edit this investor notice item", match: :first

    fill_in "Details", with: @investor_notice_item.details
    fill_in "Investor notice", with: @investor_notice_item.investor_notice_id
    fill_in "Link", with: @investor_notice_item.link
    fill_in "Title", with: @investor_notice_item.title
    click_on "Update Investor notice item"

    assert_text "Investor notice item was successfully updated"
    click_on "Back"
  end

  test "should destroy Investor notice item" do
    visit investor_notice_item_url(@investor_notice_item)
    click_on "Destroy this investor notice item", match: :first

    assert_text "Investor notice item was successfully destroyed"
  end
end
