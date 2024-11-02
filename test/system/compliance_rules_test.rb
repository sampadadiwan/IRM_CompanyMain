require "application_system_test_case"

class ComplianceRulesTest < ApplicationSystemTestCase
  setup do
    @compliance_rule = compliance_rules(:one)
  end

  test "visiting the index" do
    visit compliance_rules_url
    assert_selector "h1", text: "Compliance rules"
  end

  test "should create compliance rule" do
    visit compliance_rules_url
    click_on "New compliance rule"

    fill_in "Entity", with: @compliance_rule.entity_id
    fill_in "For class", with: @compliance_rule.for_class
    fill_in "Rule", with: @compliance_rule.rule
    fill_in "Schedule", with: @compliance_rule.schedule
    fill_in "Tags", with: @compliance_rule.tags
    click_on "Create Compliance rule"

    assert_text "Compliance rule was successfully created"
    click_on "Back"
  end

  test "should update Compliance rule" do
    visit compliance_rule_url(@compliance_rule)
    click_on "Edit this compliance rule", match: :first

    fill_in "Entity", with: @compliance_rule.entity_id
    fill_in "For class", with: @compliance_rule.for_class
    fill_in "Rule", with: @compliance_rule.rule
    fill_in "Schedule", with: @compliance_rule.schedule
    fill_in "Tags", with: @compliance_rule.tags
    click_on "Update Compliance rule"

    assert_text "Compliance rule was successfully updated"
    click_on "Back"
  end

  test "should destroy Compliance rule" do
    visit compliance_rule_url(@compliance_rule)
    click_on "Destroy this compliance rule", match: :first

    assert_text "Compliance rule was successfully destroyed"
  end
end
