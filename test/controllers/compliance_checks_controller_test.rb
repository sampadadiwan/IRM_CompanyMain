require "test_helper"

class AiChecksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @ai_check = ai_checks(:one)
  end

  test "should get index" do
    get ai_checks_url
    assert_response :success
  end

  test "should get new" do
    get new_ai_check_url
    assert_response :success
  end

  test "should create ai_check" do
    assert_difference("AiCheck.count") do
      post ai_checks_url, params: { ai_check: { entity_id: @ai_check.entity_id, explanation: @ai_check.explanation, owner_id: @ai_check.owner_id, owner_type: @ai_check.owner_type, parent_id: @ai_check.parent_id, parent_type: @ai_check.parent_type, status: @ai_check.status } }
    end

    assert_redirected_to ai_check_url(AiCheck.last)
  end

  test "should show ai_check" do
    get ai_check_url(@ai_check)
    assert_response :success
  end

  test "should get edit" do
    get edit_ai_check_url(@ai_check)
    assert_response :success
  end

  test "should update ai_check" do
    patch ai_check_url(@ai_check), params: { ai_check: { entity_id: @ai_check.entity_id, explanation: @ai_check.explanation, owner_id: @ai_check.owner_id, owner_type: @ai_check.owner_type, parent_id: @ai_check.parent_id, parent_type: @ai_check.parent_type, status: @ai_check.status } }
    assert_redirected_to ai_check_url(@ai_check)
  end

  test "should destroy ai_check" do
    assert_difference("AiCheck.count", -1) do
      delete ai_check_url(@ai_check)
    end

    assert_redirected_to ai_checks_url
  end
end
