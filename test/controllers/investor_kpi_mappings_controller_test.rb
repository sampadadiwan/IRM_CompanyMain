require "test_helper"

class InvestorKpiMappingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @investor_kpi_mapping = investor_kpi_mappings(:one)
  end

  test "should get index" do
    get investor_kpi_mappings_url
    assert_response :success
  end

  test "should get new" do
    get new_investor_kpi_mapping_url
    assert_response :success
  end

  test "should create investor_kpi_mapping" do
    assert_difference("InvestorKpiMapping.count") do
      post investor_kpi_mappings_url, params: { investor_kpi_mapping: { entity_id: @investor_kpi_mapping.entity_id, investor_id: @investor_kpi_mapping.investor_id, lower_threshhold: @investor_kpi_mapping.lower_threshhold, reported_kpi_name: @investor_kpi_mapping.reported_kpi_name, standard_kpi_name: @investor_kpi_mapping.standard_kpi_name, upper_threshold: @investor_kpi_mapping.upper_threshold } }
    end

    assert_redirected_to investor_kpi_mapping_url(InvestorKpiMapping.last)
  end

  test "should show investor_kpi_mapping" do
    get investor_kpi_mapping_url(@investor_kpi_mapping)
    assert_response :success
  end

  test "should get edit" do
    get edit_investor_kpi_mapping_url(@investor_kpi_mapping)
    assert_response :success
  end

  test "should update investor_kpi_mapping" do
    patch investor_kpi_mapping_url(@investor_kpi_mapping), params: { investor_kpi_mapping: { entity_id: @investor_kpi_mapping.entity_id, investor_id: @investor_kpi_mapping.investor_id, lower_threshhold: @investor_kpi_mapping.lower_threshhold, reported_kpi_name: @investor_kpi_mapping.reported_kpi_name, standard_kpi_name: @investor_kpi_mapping.standard_kpi_name, upper_threshold: @investor_kpi_mapping.upper_threshold } }
    assert_redirected_to investor_kpi_mapping_url(@investor_kpi_mapping)
  end

  test "should destroy investor_kpi_mapping" do
    assert_difference("InvestorKpiMapping.count", -1) do
      delete investor_kpi_mapping_url(@investor_kpi_mapping)
    end

    assert_redirected_to investor_kpi_mappings_url
  end
end
