require "test_helper"

class KpiReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @kpi_report = kpi_reports(:one)
  end

  test "should get index" do
    get kpi_reports_url
    assert_response :success
  end

  test "should get new" do
    get new_kpi_report_url
    assert_response :success
  end

  test "should create kpi_report" do
    assert_difference("KpiReport.count") do
      post kpi_reports_url, params: { kpi_report: { as_of: @kpi_report.as_of, entity_id: @kpi_report.entity_id, notes: @kpi_report.notes, user_id: @kpi_report.user_id } }
    end

    assert_redirected_to kpi_report_url(KpiReport.last)
  end

  test "should show kpi_report" do
    get kpi_report_url(@kpi_report)
    assert_response :success
  end

  test "should get edit" do
    get edit_kpi_report_url(@kpi_report)
    assert_response :success
  end

  test "should update kpi_report" do
    patch kpi_report_url(@kpi_report), params: { kpi_report: { as_of: @kpi_report.as_of, entity_id: @kpi_report.entity_id, notes: @kpi_report.notes, user_id: @kpi_report.user_id } }
    assert_redirected_to kpi_report_url(@kpi_report)
  end

  test "should destroy kpi_report" do
    assert_difference("KpiReport.count", -1) do
      delete kpi_report_url(@kpi_report)
    end

    assert_redirected_to kpi_reports_url
  end
end
