require "application_system_test_case"

class InvestorAdvisorsTest < ApplicationSystemTestCase
  setup do
    @investor_advisor = investor_advisors(:one)
  end

  test "visiting the index" do
    visit investor_advisors_url
    assert_selector "h1", text: "Investor advisors"
  end

  test "should create investor advisor" do
    visit investor_advisors_url
    click_on "New investor advisor"

    fill_in "Email", with: @investor_advisor.email
    fill_in "Entity", with: @investor_advisor.entity_id
    fill_in "User", with: @investor_advisor.user_id
    click_on "Create Investor advisor"

    assert_text "Investor advisor was successfully created"
    click_on "Back"
  end

  test "should update Investor advisor" do
    visit investor_advisor_url(@investor_advisor)
    click_on "Edit this investor advisor", match: :first

    fill_in "Email", with: @investor_advisor.email
    fill_in "Entity", with: @investor_advisor.entity_id
    fill_in "User", with: @investor_advisor.user_id
    click_on "Update Investor advisor"

    assert_text "Investor advisor was successfully updated"
    click_on "Back"
  end

  test "should destroy Investor advisor" do
    visit investor_advisor_url(@investor_advisor)
    click_on "Destroy this investor advisor", match: :first

    assert_text "Investor advisor was successfully destroyed"
  end
end
