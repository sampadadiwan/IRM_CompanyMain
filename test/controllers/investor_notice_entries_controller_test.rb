require "test_helper"

class InvestorNoticeEntriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @investor_notice_entry = investor_notice_entries(:one)
  end

  test "should get index" do
    get investor_notice_entries_url
    assert_response :success
  end

  test "should get new" do
    get new_investor_notice_entry_url
    assert_response :success
  end

  test "should create investor_notice_entry" do
    assert_difference("InvestorNoticeEntry.count") do
      post investor_notice_entries_url, params: { investor_notice_entry: { active: @investor_notice_entry.active, entity_id: @investor_notice_entry.entity_id, investor_entity_id_id: @investor_notice_entry.investor_entity_id_id, investor_id: @investor_notice_entry.investor_id, investor_notice_id: @investor_notice_entry.investor_notice_id } }
    end

    assert_redirected_to investor_notice_entry_url(InvestorNoticeEntry.last)
  end

  test "should show investor_notice_entry" do
    get investor_notice_entry_url(@investor_notice_entry)
    assert_response :success
  end

  test "should get edit" do
    get edit_investor_notice_entry_url(@investor_notice_entry)
    assert_response :success
  end

  test "should update investor_notice_entry" do
    patch investor_notice_entry_url(@investor_notice_entry), params: { investor_notice_entry: { active: @investor_notice_entry.active, entity_id: @investor_notice_entry.entity_id, investor_entity_id_id: @investor_notice_entry.investor_entity_id_id, investor_id: @investor_notice_entry.investor_id, investor_notice_id: @investor_notice_entry.investor_notice_id } }
    assert_redirected_to investor_notice_entry_url(@investor_notice_entry)
  end

  test "should destroy investor_notice_entry" do
    assert_difference("InvestorNoticeEntry.count", -1) do
      delete investor_notice_entry_url(@investor_notice_entry)
    end

    assert_redirected_to investor_notice_entries_url
  end
end
