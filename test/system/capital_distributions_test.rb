require "application_system_test_case"

class CapitalDistributionsTest < ApplicationSystemTestCase
  setup do
    @capital_distribution = capital_distributions(:one)
  end

  test "visiting the index" do
    visit capital_distributions_url
    assert_selector "h1", text: "Capital distributions"
  end

  test "should create capital distribution" do
    visit capital_distributions_url
    click_on "New capital distribution"

    fill_in "Carry", with: @capital_distribution.carry
    fill_in "Distribution date", with: @capital_distribution.distribution_date
    fill_in "Entity", with: @capital_distribution.entity_id
    fill_in "Form type", with: @capital_distribution.form_type_id
    fill_in "Fund", with: @capital_distribution.fund_id
    fill_in "Gross amount", with: @capital_distribution.gross_amount
    fill_in "Properties", with: @capital_distribution.properties
    click_on "Create Capital distribution"

    assert_text "Capital distribution was successfully created"
    click_on "Back"
  end

  test "should update Capital distribution" do
    visit capital_distribution_url(@capital_distribution)
    click_on "Edit this capital distribution", match: :first

    fill_in "Carry", with: @capital_distribution.carry
    fill_in "Distribution date", with: @capital_distribution.distribution_date
    fill_in "Entity", with: @capital_distribution.entity_id
    fill_in "Form type", with: @capital_distribution.form_type_id
    fill_in "Fund", with: @capital_distribution.fund_id
    fill_in "Gross amount", with: @capital_distribution.gross_amount
    fill_in "Properties", with: @capital_distribution.properties
    click_on "Update Capital distribution"

    assert_text "Capital distribution was successfully updated"
    click_on "Back"
  end

  test "should destroy Capital distribution" do
    visit capital_distribution_url(@capital_distribution)
    click_on "Destroy this capital distribution", match: :first

    assert_text "Capital distribution was successfully destroyed"
  end
end
