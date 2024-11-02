require "test_helper"

class ComplianceRulesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @compliance_rule = compliance_rules(:one)
  end

  test "should get index" do
    get compliance_rules_url
    assert_response :success
  end

  test "should get new" do
    get new_compliance_rule_url
    assert_response :success
  end

  test "should create compliance_rule" do
    assert_difference("ComplianceRule.count") do
      post compliance_rules_url, params: { compliance_rule: { entity_id: @compliance_rule.entity_id, for_class: @compliance_rule.for_class, rule: @compliance_rule.rule, schedule: @compliance_rule.schedule, tags: @compliance_rule.tags } }
    end

    assert_redirected_to compliance_rule_url(ComplianceRule.last)
  end

  test "should show compliance_rule" do
    get compliance_rule_url(@compliance_rule)
    assert_response :success
  end

  test "should get edit" do
    get edit_compliance_rule_url(@compliance_rule)
    assert_response :success
  end

  test "should update compliance_rule" do
    patch compliance_rule_url(@compliance_rule), params: { compliance_rule: { entity_id: @compliance_rule.entity_id, for_class: @compliance_rule.for_class, rule: @compliance_rule.rule, schedule: @compliance_rule.schedule, tags: @compliance_rule.tags } }
    assert_redirected_to compliance_rule_url(@compliance_rule)
  end

  test "should destroy compliance_rule" do
    assert_difference("ComplianceRule.count", -1) do
      delete compliance_rule_url(@compliance_rule)
    end

    assert_redirected_to compliance_rules_url
  end
end
