require "application_system_test_case"

class KpiReportsTest < ApplicationSystemTestCase
  setup do
    @kpi_report = kpi_reports(:one)
  end

  test "visiting the index" do
    visit kpi_reports_url
    assert_selector "h1", text: "Kpi reports"
  end

  test "should create kpi report" do
    visit kpi_reports_url
    click_on "New kpi report"

    fill_in "As of", with: @kpi_report.as_of
    fill_in "Entity", with: @kpi_report.entity_id
    fill_in "Notes", with: @kpi_report.notes
    fill_in "User", with: @kpi_report.user_id
    click_on "Create Kpi report"

    assert_text "Kpi report was successfully created"
    click_on "Back"
  end

  test "should update Kpi report" do
    visit kpi_report_url(@kpi_report)
    click_on "Edit this kpi report", match: :first

    fill_in "As of", with: @kpi_report.as_of
    fill_in "Entity", with: @kpi_report.entity_id
    fill_in "Notes", with: @kpi_report.notes
    fill_in "User", with: @kpi_report.user_id
    click_on "Update Kpi report"

    assert_text "Kpi report was successfully updated"
    click_on "Back"
  end

  test "should destroy Kpi report" do
    visit kpi_report_url(@kpi_report)
    click_on "Destroy this kpi report", match: :first

    assert_text "Kpi report was successfully destroyed"
  end
end
