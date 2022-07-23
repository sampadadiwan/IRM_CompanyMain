require "application_system_test_case"

class ExpressionOfInterestsTest < ApplicationSystemTestCase
  setup do
    @expression_of_interest = expression_of_interests(:one)
  end

  test "visiting the index" do
    visit expression_of_interests_url
    assert_selector "h1", text: "Expression of interests"
  end

  test "should create expression of interest" do
    visit expression_of_interests_url
    click_on "New expression of interest"

    fill_in "Investmentopportunity", with: @expression_of_interest.InvestmentOpportunity_id
    fill_in "Allocation amount cents", with: @expression_of_interest.allocation_amount_cents
    fill_in "Allocation percentage", with: @expression_of_interest.allocation_percentage
    fill_in "Amount cents", with: @expression_of_interest.amount_cents
    check "Approved" if @expression_of_interest.approved
    fill_in "Entity", with: @expression_of_interest.entity_id
    fill_in "Eoi entity", with: @expression_of_interest.eoi_entity_id
    fill_in "User", with: @expression_of_interest.user_id
    check "Verified" if @expression_of_interest.verified
    click_on "Create Expression of interest"

    assert_text "Expression of interest was successfully created"
    click_on "Back"
  end

  test "should update Expression of interest" do
    visit expression_of_interest_url(@expression_of_interest)
    click_on "Edit this expression of interest", match: :first

    fill_in "Investmentopportunity", with: @expression_of_interest.InvestmentOpportunity_id
    fill_in "Allocation amount cents", with: @expression_of_interest.allocation_amount_cents
    fill_in "Allocation percentage", with: @expression_of_interest.allocation_percentage
    fill_in "Amount cents", with: @expression_of_interest.amount_cents
    check "Approved" if @expression_of_interest.approved
    fill_in "Entity", with: @expression_of_interest.entity_id
    fill_in "Eoi entity", with: @expression_of_interest.eoi_entity_id
    fill_in "User", with: @expression_of_interest.user_id
    check "Verified" if @expression_of_interest.verified
    click_on "Update Expression of interest"

    assert_text "Expression of interest was successfully updated"
    click_on "Back"
  end

  test "should destroy Expression of interest" do
    visit expression_of_interest_url(@expression_of_interest)
    click_on "Destroy this expression of interest", match: :first

    assert_text "Expression of interest was successfully destroyed"
  end
end
