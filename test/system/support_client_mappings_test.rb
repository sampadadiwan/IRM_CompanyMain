require "application_system_test_case"

class SupportClientMappingsTest < ApplicationSystemTestCase
  setup do
    @support_client_mapping = support_client_mappings(:one)
  end

  test "visiting the index" do
    visit support_client_mappings_url
    assert_selector "h1", text: "Support client mappings"
  end

  test "should create support client mapping" do
    visit support_client_mappings_url
    click_on "New support client mapping"

    fill_in "End date", with: @support_client_mapping.end_date
    fill_in "Entity", with: @support_client_mapping.entity_id
    fill_in "User", with: @support_client_mapping.user_id
    click_on "Create Support client mapping"

    assert_text "Support client mapping was successfully created"
    click_on "Back"
  end

  test "should update Support client mapping" do
    visit support_client_mapping_url(@support_client_mapping)
    click_on "Edit this support client mapping", match: :first

    fill_in "End date", with: @support_client_mapping.end_date
    fill_in "Entity", with: @support_client_mapping.entity_id
    fill_in "User", with: @support_client_mapping.user_id
    click_on "Update Support client mapping"

    assert_text "Support client mapping was successfully updated"
    click_on "Back"
  end

  test "should destroy Support client mapping" do
    visit support_client_mapping_url(@support_client_mapping)
    click_on "Destroy this support client mapping", match: :first

    assert_text "Support client mapping was successfully destroyed"
  end
end
