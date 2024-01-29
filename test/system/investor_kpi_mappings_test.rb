require "application_system_test_case"

class InvestorKpiMappingsTest < ApplicationSystemTestCase
  setup do
    @investor_kpi_mapping = investor_kpi_mappings(:one)
  end

  test "visiting the index" do
    visit investor_kpi_mappings_url
    assert_selector "h1", text: "Investor kpi mappings"
  end

  test "should create investor kpi mapping" do
    visit investor_kpi_mappings_url
    click_on "New investor kpi mapping"

    fill_in "Entity", with: @investor_kpi_mapping.entity_id
    fill_in "Investor", with: @investor_kpi_mapping.investor_id
    fill_in "Lower threshhold", with: @investor_kpi_mapping.lower_threshhold
    fill_in "Reported kpi name", with: @investor_kpi_mapping.reported_kpi_name
    fill_in "Standard kpi name", with: @investor_kpi_mapping.standard_kpi_name
    fill_in "Upper threshold", with: @investor_kpi_mapping.upper_threshold
    click_on "Create Investor kpi mapping"

    assert_text "Investor kpi mapping was successfully created"
    click_on "Back"
  end

  test "should update Investor kpi mapping" do
    visit investor_kpi_mapping_url(@investor_kpi_mapping)
    click_on "Edit this investor kpi mapping", match: :first

    fill_in "Entity", with: @investor_kpi_mapping.entity_id
    fill_in "Investor", with: @investor_kpi_mapping.investor_id
    fill_in "Lower threshhold", with: @investor_kpi_mapping.lower_threshhold
    fill_in "Reported kpi name", with: @investor_kpi_mapping.reported_kpi_name
    fill_in "Standard kpi name", with: @investor_kpi_mapping.standard_kpi_name
    fill_in "Upper threshold", with: @investor_kpi_mapping.upper_threshold
    click_on "Update Investor kpi mapping"

    assert_text "Investor kpi mapping was successfully updated"
    click_on "Back"
  end

  test "should destroy Investor kpi mapping" do
    visit investor_kpi_mapping_url(@investor_kpi_mapping)
    click_on "Destroy this investor kpi mapping", match: :first

    assert_text "Investor kpi mapping was successfully destroyed"
  end
end
