require "test_helper"

class ComplianceChecksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @compliance_check = compliance_checks(:one)
  end

  test "should get index" do
    get compliance_checks_url
    assert_response :success
  end

  test "should get new" do
    get new_compliance_check_url
    assert_response :success
  end

  test "should create compliance_check" do
    assert_difference("ComplianceCheck.count") do
      post compliance_checks_url, params: { compliance_check: { entity_id: @compliance_check.entity_id, explanation: @compliance_check.explanation, owner_id: @compliance_check.owner_id, owner_type: @compliance_check.owner_type, parent_id: @compliance_check.parent_id, parent_type: @compliance_check.parent_type, status: @compliance_check.status } }
    end

    assert_redirected_to compliance_check_url(ComplianceCheck.last)
  end

  test "should show compliance_check" do
    get compliance_check_url(@compliance_check)
    assert_response :success
  end

  test "should get edit" do
    get edit_compliance_check_url(@compliance_check)
    assert_response :success
  end

  test "should update compliance_check" do
    patch compliance_check_url(@compliance_check), params: { compliance_check: { entity_id: @compliance_check.entity_id, explanation: @compliance_check.explanation, owner_id: @compliance_check.owner_id, owner_type: @compliance_check.owner_type, parent_id: @compliance_check.parent_id, parent_type: @compliance_check.parent_type, status: @compliance_check.status } }
    assert_redirected_to compliance_check_url(@compliance_check)
  end

  test "should destroy compliance_check" do
    assert_difference("ComplianceCheck.count", -1) do
      delete compliance_check_url(@compliance_check)
    end

    assert_redirected_to compliance_checks_url
  end
end
