require "application_system_test_case"

class AiChecksTest < ApplicationSystemTestCase
  setup do
    @ai_check = ai_checks(:one)
  end

  test "visiting the index" do
    visit ai_checks_url
    assert_selector "h1", text: "Compliance checks"
  end

  test "should create compliance check" do
    visit ai_checks_url
    click_on "New compliance check"

    fill_in "Entity", with: @ai_check.entity_id
    fill_in "Explanation", with: @ai_check.explanation
    fill_in "Owner", with: @ai_check.owner_id
    fill_in "Owner type", with: @ai_check.owner_type
    fill_in "Parent", with: @ai_check.parent_id
    fill_in "Parent type", with: @ai_check.parent_type
    fill_in "Status", with: @ai_check.status
    click_on "Create Compliance check"

    assert_text "Compliance check was successfully created"
    click_on "Back"
  end

  test "should update Compliance check" do
    visit ai_check_url(@ai_check)
    click_on "Edit this compliance check", match: :first

    fill_in "Entity", with: @ai_check.entity_id
    fill_in "Explanation", with: @ai_check.explanation
    fill_in "Owner", with: @ai_check.owner_id
    fill_in "Owner type", with: @ai_check.owner_type
    fill_in "Parent", with: @ai_check.parent_id
    fill_in "Parent type", with: @ai_check.parent_type
    fill_in "Status", with: @ai_check.status
    click_on "Update Compliance check"

    assert_text "Compliance check was successfully updated"
    click_on "Back"
  end

  test "should destroy Compliance check" do
    visit ai_check_url(@ai_check)
    click_on "Destroy this compliance check", match: :first

    assert_text "Compliance check was successfully destroyed"
  end
end
