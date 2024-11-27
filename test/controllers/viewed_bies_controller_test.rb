require "test_helper"

class ViewedBiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @viewed_by = viewed_bies(:one)
  end

  test "should get index" do
    get viewed_bies_url
    assert_response :success
  end

  test "should get new" do
    get new_viewed_by_url
    assert_response :success
  end

  test "should create viewed_by" do
    assert_difference("ViewedBy.count") do
      post viewed_bies_url, params: { viewed_by: { owner_id: @viewed_by.owner_id, owner_type: @viewed_by.owner_type, user_id: @viewed_by.user_id } }
    end

    assert_redirected_to viewed_by_url(ViewedBy.last)
  end

  test "should show viewed_by" do
    get viewed_by_url(@viewed_by)
    assert_response :success
  end

  test "should get edit" do
    get edit_viewed_by_url(@viewed_by)
    assert_response :success
  end

  test "should update viewed_by" do
    patch viewed_by_url(@viewed_by), params: { viewed_by: { owner_id: @viewed_by.owner_id, owner_type: @viewed_by.owner_type, user_id: @viewed_by.user_id } }
    assert_redirected_to viewed_by_url(@viewed_by)
  end

  test "should destroy viewed_by" do
    assert_difference("ViewedBy.count", -1) do
      delete viewed_by_url(@viewed_by)
    end

    assert_redirected_to viewed_bies_url
  end
end
