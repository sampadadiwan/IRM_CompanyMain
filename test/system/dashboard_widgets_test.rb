require "application_system_test_case"

class DashboardWidgetsTest < ApplicationSystemTestCase
  setup do
    @dashboard_widget = dashboard_widgets(:one)
  end

  test "visiting the index" do
    visit dashboard_widgets_url
    assert_selector "h1", text: "Dashboard widgets"
  end

  test "should create dashboard widget" do
    visit dashboard_widgets_url
    click_on "New dashboard widget"

    check "Enabled" if @dashboard_widget.enabled
    fill_in "Entity", with: @dashboard_widget.entity_id
    fill_in "Metadata", with: @dashboard_widget.metadata
    fill_in "Name", with: @dashboard_widget.widget_name
    fill_in "Owner", with: @dashboard_widget.owner_id
    fill_in "Owner type", with: @dashboard_widget.owner_type
    fill_in "Position", with: @dashboard_widget.position
    fill_in "Template", with: @dashboard_widget.template
    click_on "Create Dashboard widget"

    assert_text "Dashboard widget was successfully created"
    click_on "Back"
  end

  test "should update Dashboard widget" do
    visit dashboard_widget_url(@dashboard_widget)
    click_on "Edit this dashboard widget", match: :first

    check "Enabled" if @dashboard_widget.enabled
    fill_in "Entity", with: @dashboard_widget.entity_id
    fill_in "Metadata", with: @dashboard_widget.metadata
    fill_in "Name", with: @dashboard_widget.widget_name
    fill_in "Owner", with: @dashboard_widget.owner_id
    fill_in "Owner type", with: @dashboard_widget.owner_type
    fill_in "Position", with: @dashboard_widget.position
    fill_in "Template", with: @dashboard_widget.template
    click_on "Update Dashboard widget"

    assert_text "Dashboard widget was successfully updated"
    click_on "Back"
  end

  test "should destroy Dashboard widget" do
    visit dashboard_widget_url(@dashboard_widget)
    click_on "Destroy this dashboard widget", match: :first

    assert_text "Dashboard widget was successfully destroyed"
  end
end
