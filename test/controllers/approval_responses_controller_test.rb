require "test_helper"

class ApprovalResponsesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @approval_response = approval_responses(:one)
  end

  test "should get index" do
    get approval_responses_url
    assert_response :success
  end

  test "should get new" do
    get new_approval_response_url
    assert_response :success
  end

  test "should create approval_response" do
    assert_difference("ApprovalResponse.count") do
      post approval_responses_url, params: { approval_response: { approval_id: @approval_response.approval_id, entity_id: @approval_response.entity_id, status: @approval_response.status } }
    end

    assert_redirected_to approval_response_url(ApprovalResponse.last)
  end

  test "should show approval_response" do
    get approval_response_url(@approval_response)
    assert_response :success
  end

  test "should get edit" do
    get edit_approval_response_url(@approval_response)
    assert_response :success
  end

  test "should update approval_response" do
    patch approval_response_url(@approval_response), params: { approval_response: { approval_id: @approval_response.approval_id, entity_id: @approval_response.entity_id, status: @approval_response.status } }
    assert_redirected_to approval_response_url(@approval_response)
  end

  test "should destroy approval_response" do
    assert_difference("ApprovalResponse.count", -1) do
      delete approval_response_url(@approval_response)
    end

    assert_redirected_to approval_responses_url
  end
end
