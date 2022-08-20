require "application_system_test_case"

class CapitalCommitmentsTest < ApplicationSystemTestCase
  setup do
    @capital_commitment = capital_commitments(:one)
  end

  test "visiting the index" do
    visit capital_commitments_url
    assert_selector "h1", text: "Capital commitments"
  end

  test "should create capital commitment" do
    visit capital_commitments_url
    click_on "New capital commitment"

    fill_in "Collected amount", with: @capital_commitment.collected_amount
    fill_in "Committed amount", with: @capital_commitment.committed_amount
    fill_in "Entity", with: @capital_commitment.entity_id
    fill_in "Fund", with: @capital_commitment.fund_id
    fill_in "Investor", with: @capital_commitment.investor_id
    fill_in "Notes", with: @capital_commitment.notes
    click_on "Create Capital commitment"

    assert_text "Capital commitment was successfully created"
    click_on "Back"
  end

  test "should update Capital commitment" do
    visit capital_commitment_url(@capital_commitment)
    click_on "Edit this capital commitment", match: :first

    fill_in "Collected amount", with: @capital_commitment.collected_amount
    fill_in "Committed amount", with: @capital_commitment.committed_amount
    fill_in "Entity", with: @capital_commitment.entity_id
    fill_in "Fund", with: @capital_commitment.fund_id
    fill_in "Investor", with: @capital_commitment.investor_id
    fill_in "Notes", with: @capital_commitment.notes
    click_on "Update Capital commitment"

    assert_text "Capital commitment was successfully updated"
    click_on "Back"
  end

  test "should destroy Capital commitment" do
    visit capital_commitment_url(@capital_commitment)
    click_on "Destroy this capital commitment", match: :first

    assert_text "Capital commitment was successfully destroyed"
  end
end
