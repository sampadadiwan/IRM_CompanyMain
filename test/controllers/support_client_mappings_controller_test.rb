require "test_helper"

class SupportClientMappingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @support_client_mapping = support_client_mappings(:one)
  end

  test "should get index" do
    get support_client_mappings_url
    assert_response :success
  end

  test "should get new" do
    get new_support_client_mapping_url
    assert_response :success
  end

  test "should create support_client_mapping" do
    assert_difference("SupportClientMapping.count") do
      post support_client_mappings_url, params: { support_client_mapping: { end_date: @support_client_mapping.end_date, entity_id: @support_client_mapping.entity_id, user_id: @support_client_mapping.user_id } }
    end

    assert_redirected_to support_client_mapping_url(SupportClientMapping.last)
  end

  test "should show support_client_mapping" do
    get support_client_mapping_url(@support_client_mapping)
    assert_response :success
  end

  test "should get edit" do
    get edit_support_client_mapping_url(@support_client_mapping)
    assert_response :success
  end

  test "should update support_client_mapping" do
    patch support_client_mapping_url(@support_client_mapping), params: { support_client_mapping: { end_date: @support_client_mapping.end_date, entity_id: @support_client_mapping.entity_id, user_id: @support_client_mapping.user_id } }
    assert_redirected_to support_client_mapping_url(@support_client_mapping)
  end

  test "should destroy support_client_mapping" do
    assert_difference("SupportClientMapping.count", -1) do
      delete support_client_mapping_url(@support_client_mapping)
    end

    assert_redirected_to support_client_mappings_url
  end
end
