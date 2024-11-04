require "application_system_test_case"

class AiRulesTest < ApplicationSystemTestCase
  setup do
    @ai_rule = ai_rules(:one)
  end

  test "visiting the index" do
    visit ai_rules_url
    assert_selector "h1", text: "Compliance rules"
  end

  test "should create compliance rule" do
    visit ai_rules_url
    click_on "New compliance rule"

    fill_in "Entity", with: @ai_rule.entity_id
    fill_in "For class", with: @ai_rule.for_class
    fill_in "Rule", with: @ai_rule.rule
    fill_in "Schedule", with: @ai_rule.schedule
    fill_in "Tags", with: @ai_rule.tags
    click_on "Create Compliance rule"

    assert_text "Compliance rule was successfully created"
    click_on "Back"
  end

  test "should update Compliance rule" do
    visit ai_rule_url(@ai_rule)
    click_on "Edit this compliance rule", match: :first

    fill_in "Entity", with: @ai_rule.entity_id
    fill_in "For class", with: @ai_rule.for_class
    fill_in "Rule", with: @ai_rule.rule
    fill_in "Schedule", with: @ai_rule.schedule
    fill_in "Tags", with: @ai_rule.tags
    click_on "Update Compliance rule"

    assert_text "Compliance rule was successfully updated"
    click_on "Back"
  end

  test "should destroy Compliance rule" do
    visit ai_rule_url(@ai_rule)
    click_on "Destroy this compliance rule", match: :first

    assert_text "Compliance rule was successfully destroyed"
  end
end
