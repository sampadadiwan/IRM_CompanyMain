require "test_helper"

class AiRulesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @ai_rule = ai_rules(:one)
  end

  test "should get index" do
    get ai_rules_url
    assert_response :success
  end

  test "should get new" do
    get new_ai_rule_url
    assert_response :success
  end

  test "should create ai_rule" do
    assert_difference("AiRule.count") do
      post ai_rules_url, params: { ai_rule: { entity_id: @ai_rule.entity_id, for_class: @ai_rule.for_class, rule: @ai_rule.rule, schedule: @ai_rule.schedule, tags: @ai_rule.tags } }
    end

    assert_redirected_to ai_rule_url(AiRule.last)
  end

  test "should show ai_rule" do
    get ai_rule_url(@ai_rule)
    assert_response :success
  end

  test "should get edit" do
    get edit_ai_rule_url(@ai_rule)
    assert_response :success
  end

  test "should update ai_rule" do
    patch ai_rule_url(@ai_rule), params: { ai_rule: { entity_id: @ai_rule.entity_id, for_class: @ai_rule.for_class, rule: @ai_rule.rule, schedule: @ai_rule.schedule, tags: @ai_rule.tags } }
    assert_redirected_to ai_rule_url(@ai_rule)
  end

  test "should destroy ai_rule" do
    assert_difference("AiRule.count", -1) do
      delete ai_rule_url(@ai_rule)
    end

    assert_redirected_to ai_rules_url
  end
end
