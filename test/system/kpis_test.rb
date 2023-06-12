require "application_system_test_case"

class KpisTest < ApplicationSystemTestCase
  setup do
    @kpi = kpis(:one)
  end

  test "visiting the index" do
    visit kpis_url
    assert_selector "h1", text: "Kpis"
  end

  test "should create kpi" do
    visit kpis_url
    click_on "New kpi"

    fill_in "Display value", with: @kpi.display_value
    fill_in "Entity", with: @kpi.entity_id
    fill_in "Kpi report", with: @kpi.kpi_report_id
    fill_in "Name", with: @kpi.name
    fill_in "Notes", with: @kpi.notes
    fill_in "Value", with: @kpi.value
    click_on "Create Kpi"

    assert_text "Kpi was successfully created"
    click_on "Back"
  end

  test "should update Kpi" do
    visit kpi_url(@kpi)
    click_on "Edit this kpi", match: :first

    fill_in "Display value", with: @kpi.display_value
    fill_in "Entity", with: @kpi.entity_id
    fill_in "Kpi report", with: @kpi.kpi_report_id
    fill_in "Name", with: @kpi.name
    fill_in "Notes", with: @kpi.notes
    fill_in "Value", with: @kpi.value
    click_on "Update Kpi"

    assert_text "Kpi was successfully updated"
    click_on "Back"
  end

  test "should destroy Kpi" do
    visit kpi_url(@kpi)
    click_on "Destroy this kpi", match: :first

    assert_text "Kpi was successfully destroyed"
  end
end
