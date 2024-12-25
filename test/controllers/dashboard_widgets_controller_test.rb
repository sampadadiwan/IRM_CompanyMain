require "test_helper"

class DashboardWidgetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @dashboard_widget = dashboard_widgets(:one)
  end

  test "should get index" do
    get dashboard_widgets_url
    assert_response :success
  end

  test "should get new" do
    get new_dashboard_widget_url
    assert_response :success
  end

  test "should create dashboard_widget" do
    assert_difference("DashboardWidget.count") do
      post dashboard_widgets_url, params: { dashboard_widget: { enabled: @dashboard_widget.enabled, entity_id: @dashboard_widget.entity_id, metadata: @dashboard_widget.metadata, name: @dashboard_widget.widget_name, owner_id: @dashboard_widget.owner_id, owner_type: @dashboard_widget.owner_type, position: @dashboard_widget.position, template: @dashboard_widget.template } }
    end

    assert_redirected_to dashboard_widget_url(DashboardWidget.last)
  end

  test "should show dashboard_widget" do
    get dashboard_widget_url(@dashboard_widget)
    assert_response :success
  end

  test "should get edit" do
    get edit_dashboard_widget_url(@dashboard_widget)
    assert_response :success
  end

  test "should update dashboard_widget" do
    patch dashboard_widget_url(@dashboard_widget), params: { dashboard_widget: { enabled: @dashboard_widget.enabled, entity_id: @dashboard_widget.entity_id, metadata: @dashboard_widget.metadata, name: @dashboard_widget.widget_name, owner_id: @dashboard_widget.owner_id, owner_type: @dashboard_widget.owner_type, position: @dashboard_widget.position, template: @dashboard_widget.template } }
    assert_redirected_to dashboard_widget_url(@dashboard_widget)
  end

  test "should destroy dashboard_widget" do
    assert_difference("DashboardWidget.count", -1) do
      delete dashboard_widget_url(@dashboard_widget)
    end

    assert_redirected_to dashboard_widgets_url
  end
end
