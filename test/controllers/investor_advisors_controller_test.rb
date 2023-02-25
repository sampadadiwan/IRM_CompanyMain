require "test_helper"

class InvestorAdvisorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @investor_advisor = investor_advisors(:one)
  end

  test "should get index" do
    get investor_advisors_url
    assert_response :success
  end

  test "should get new" do
    get new_investor_advisor_url
    assert_response :success
  end

  test "should create investor_advisor" do
    assert_difference("InvestorAdvisor.count") do
      post investor_advisors_url, params: { investor_advisor: { email: @investor_advisor.email, entity_id: @investor_advisor.entity_id, user_id: @investor_advisor.user_id } }
    end

    assert_redirected_to investor_advisor_url(InvestorAdvisor.last)
  end

  test "should show investor_advisor" do
    get investor_advisor_url(@investor_advisor)
    assert_response :success
  end

  test "should get edit" do
    get edit_investor_advisor_url(@investor_advisor)
    assert_response :success
  end

  test "should update investor_advisor" do
    patch investor_advisor_url(@investor_advisor), params: { investor_advisor: { email: @investor_advisor.email, entity_id: @investor_advisor.entity_id, user_id: @investor_advisor.user_id } }
    assert_redirected_to investor_advisor_url(@investor_advisor)
  end

  test "should destroy investor_advisor" do
    assert_difference("InvestorAdvisor.count", -1) do
      delete investor_advisor_url(@investor_advisor)
    end

    assert_redirected_to investor_advisors_url
  end
end
