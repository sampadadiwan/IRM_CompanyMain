require "test_helper"

class InvestorNoticesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @investor_notice = investor_notices(:one)
  end

  test "should get index" do
    get investor_notices_url
    assert_response :success
  end

  test "should get new" do
    get new_investor_notice_url
    assert_response :success
  end

  test "should create investor_notice" do
    assert_difference("InvestorNotice.count") do
      post investor_notices_url, params: { investor_notice: { active: @investor_notice.active, end_date: @investor_notice.end_date, entity_id: @investor_notice.entity_id, investor_entity_id_id: @investor_notice.investor_entity_id_id, investor_id: @investor_notice.investor_id, start_date: @investor_notice.start_date } }
    end

    assert_redirected_to investor_notice_url(InvestorNotice.last)
  end

  test "should show investor_notice" do
    get investor_notice_url(@investor_notice)
    assert_response :success
  end

  test "should get edit" do
    get edit_investor_notice_url(@investor_notice)
    assert_response :success
  end

  test "should update investor_notice" do
    patch investor_notice_url(@investor_notice), params: { investor_notice: { active: @investor_notice.active, end_date: @investor_notice.end_date, entity_id: @investor_notice.entity_id, investor_entity_id_id: @investor_notice.investor_entity_id_id, investor_id: @investor_notice.investor_id, start_date: @investor_notice.start_date } }
    assert_redirected_to investor_notice_url(@investor_notice)
  end

  test "should destroy investor_notice" do
    assert_difference("InvestorNotice.count", -1) do
      delete investor_notice_url(@investor_notice)
    end

    assert_redirected_to investor_notices_url
  end
end
