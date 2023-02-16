require "application_system_test_case"

class FundFormulasTest < ApplicationSystemTestCase
  setup do
    @fund_formula = fund_formulas(:one)
  end

  test "visiting the index" do
    visit fund_formulas_url
    assert_selector "h1", text: "Fund formulas"
  end

  test "should create fund formula" do
    visit fund_formulas_url
    click_on "New fund formula"

    fill_in "Description", with: @fund_formula.description
    fill_in "Formula", with: @fund_formula.formula
    fill_in "Fund", with: @fund_formula.fund_id
    fill_in "Name", with: @fund_formula.name
    click_on "Create Fund formula"

    assert_text "Fund formula was successfully created"
    click_on "Back"
  end

  test "should update Fund formula" do
    visit fund_formula_url(@fund_formula)
    click_on "Edit this fund formula", match: :first

    fill_in "Description", with: @fund_formula.description
    fill_in "Formula", with: @fund_formula.formula
    fill_in "Fund", with: @fund_formula.fund_id
    fill_in "Name", with: @fund_formula.name
    click_on "Update Fund formula"

    assert_text "Fund formula was successfully updated"
    click_on "Back"
  end

  test "should destroy Fund formula" do
    visit fund_formula_url(@fund_formula)
    click_on "Destroy this fund formula", match: :first

    assert_text "Fund formula was successfully destroyed"
  end
end
