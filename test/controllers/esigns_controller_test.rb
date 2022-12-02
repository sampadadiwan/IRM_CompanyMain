require "test_helper"

class EsignsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @esign = esigns(:one)
  end

  test "should get index" do
    get esigns_url
    assert_response :success
  end

  test "should get new" do
    get new_esign_url
    assert_response :success
  end

  test "should create esign" do
    assert_difference("Esign.count") do
      post esigns_url, params: { esign: { completed: @esign.completed, entity_id: @esign.entity_id, link: @esign.link, owner_id: @esign.owner_id, owner_type: @esign.owner_type, reason: @esign.reason, sequence: @esign.sequence, status: @esign.status, user_id: @esign.user_id } }
    end

    assert_redirected_to esign_url(Esign.last)
  end

  test "should show esign" do
    get esign_url(@esign)
    assert_response :success
  end

  test "should get edit" do
    get edit_esign_url(@esign)
    assert_response :success
  end

  test "should update esign" do
    patch esign_url(@esign), params: { esign: { completed: @esign.completed, entity_id: @esign.entity_id, link: @esign.link, owner_id: @esign.owner_id, owner_type: @esign.owner_type, reason: @esign.reason, sequence: @esign.sequence, status: @esign.status, user_id: @esign.user_id } }
    assert_redirected_to esign_url(@esign)
  end

  test "should destroy esign" do
    assert_difference("Esign.count", -1) do
      delete esign_url(@esign)
    end

    assert_redirected_to esigns_url
  end
end
