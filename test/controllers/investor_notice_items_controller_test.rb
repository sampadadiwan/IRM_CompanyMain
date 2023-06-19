require "test_helper"

class InvestorNoticeItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @investor_notice_item = investor_notice_items(:one)
  end

  test "should get index" do
    get investor_notice_items_url
    assert_response :success
  end

  test "should get new" do
    get new_investor_notice_item_url
    assert_response :success
  end

  test "should create investor_notice_item" do
    assert_difference("InvestorNoticeItem.count") do
      post investor_notice_items_url, params: { investor_notice_item: { details: @investor_notice_item.details, investor_notice_id: @investor_notice_item.investor_notice_id, link: @investor_notice_item.link, title: @investor_notice_item.title } }
    end

    assert_redirected_to investor_notice_item_url(InvestorNoticeItem.last)
  end

  test "should show investor_notice_item" do
    get investor_notice_item_url(@investor_notice_item)
    assert_response :success
  end

  test "should get edit" do
    get edit_investor_notice_item_url(@investor_notice_item)
    assert_response :success
  end

  test "should update investor_notice_item" do
    patch investor_notice_item_url(@investor_notice_item), params: { investor_notice_item: { details: @investor_notice_item.details, investor_notice_id: @investor_notice_item.investor_notice_id, link: @investor_notice_item.link, title: @investor_notice_item.title } }
    assert_redirected_to investor_notice_item_url(@investor_notice_item)
  end

  test "should destroy investor_notice_item" do
    assert_difference("InvestorNoticeItem.count", -1) do
      delete investor_notice_item_url(@investor_notice_item)
    end

    assert_redirected_to investor_notice_items_url
  end
end
