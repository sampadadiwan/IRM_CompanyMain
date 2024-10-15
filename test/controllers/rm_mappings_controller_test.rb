require "test_helper"

class RmMappingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @rm_mapping = rm_mappings(:one)
  end

  test "should get index" do
    get rm_mappings_url
    assert_response :success
  end

  test "should get new" do
    get new_rm_mapping_url
    assert_response :success
  end

  test "should create rm_mapping" do
    assert_difference("RmMapping.count") do
      post rm_mappings_url, params: { rm_mapping: { approved: @rm_mapping.approved, entity_id: @rm_mapping.entity_id, investor_id: @rm_mapping.investor_id, permissions: @rm_mapping.permissions, rm_id: @rm_mapping.rm_id } }
    end

    assert_redirected_to rm_mapping_url(RmMapping.last)
  end

  test "should show rm_mapping" do
    get rm_mapping_url(@rm_mapping)
    assert_response :success
  end

  test "should get edit" do
    get edit_rm_mapping_url(@rm_mapping)
    assert_response :success
  end

  test "should update rm_mapping" do
    patch rm_mapping_url(@rm_mapping), params: { rm_mapping: { approved: @rm_mapping.approved, entity_id: @rm_mapping.entity_id, investor_id: @rm_mapping.investor_id, permissions: @rm_mapping.permissions, rm_id: @rm_mapping.rm_id } }
    assert_redirected_to rm_mapping_url(@rm_mapping)
  end

  test "should destroy rm_mapping" do
    assert_difference("RmMapping.count", -1) do
      delete rm_mapping_url(@rm_mapping)
    end

    assert_redirected_to rm_mappings_url
  end
end
