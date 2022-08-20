require "application_system_test_case"

class CapitalCallsTest < ApplicationSystemTestCase
  setup do
    @capital_call = capital_calls(:one)
  end

  test "visiting the index" do
    visit capital_calls_url
    assert_selector "h1", text: "Capital calls"
  end

  test "should create capital call" do
    visit capital_calls_url
    click_on "New capital call"

    fill_in "Due date", with: @capital_call.due_date
    fill_in "Entity", with: @capital_call.entity_id
    fill_in "Fund", with: @capital_call.fund_id
    fill_in "Name", with: @capital_call.name
    fill_in "Notes", with: @capital_call.notes
    fill_in "Percentage called", with: @capital_call.percentage_called
    click_on "Create Capital call"

    assert_text "Capital call was successfully created"
    click_on "Back"
  end

  test "should update Capital call" do
    visit capital_call_url(@capital_call)
    click_on "Edit this capital call", match: :first

    fill_in "Due date", with: @capital_call.due_date
    fill_in "Entity", with: @capital_call.entity_id
    fill_in "Fund", with: @capital_call.fund_id
    fill_in "Name", with: @capital_call.name
    fill_in "Notes", with: @capital_call.notes
    fill_in "Percentage called", with: @capital_call.percentage_called
    click_on "Update Capital call"

    assert_text "Capital call was successfully updated"
    click_on "Back"
  end

  test "should destroy Capital call" do
    visit capital_call_url(@capital_call)
    click_on "Destroy this capital call", match: :first

    assert_text "Capital call was successfully destroyed"
  end
end
