require "application_system_test_case"

class RmMappingsTest < ApplicationSystemTestCase
  setup do
    @rm_mapping = rm_mappings(:one)
  end

  test "visiting the index" do
    visit rm_mappings_url
    assert_selector "h1", text: "Rm mappings"
  end

  test "should create rm mapping" do
    visit rm_mappings_url
    click_on "New rm mapping"

    check "Approved" if @rm_mapping.approved
    fill_in "Entity", with: @rm_mapping.entity_id
    fill_in "Investor", with: @rm_mapping.investor_id
    fill_in "Permissions", with: @rm_mapping.permissions
    fill_in "Rm", with: @rm_mapping.rm_id
    click_on "Create Rm mapping"

    assert_text "Rm mapping was successfully created"
    click_on "Back"
  end

  test "should update Rm mapping" do
    visit rm_mapping_url(@rm_mapping)
    click_on "Edit this rm mapping", match: :first

    check "Approved" if @rm_mapping.approved
    fill_in "Entity", with: @rm_mapping.entity_id
    fill_in "Investor", with: @rm_mapping.investor_id
    fill_in "Permissions", with: @rm_mapping.permissions
    fill_in "Rm", with: @rm_mapping.rm_id
    click_on "Update Rm mapping"

    assert_text "Rm mapping was successfully updated"
    click_on "Back"
  end

  test "should destroy Rm mapping" do
    visit rm_mapping_url(@rm_mapping)
    click_on "Destroy this rm mapping", match: :first

    assert_text "Rm mapping was successfully destroyed"
  end
end
