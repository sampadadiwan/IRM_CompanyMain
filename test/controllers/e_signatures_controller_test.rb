require "test_helper"

class ESignaturesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @e_signature = e_signatures(:one)
  end

  test "should get index" do
    get e_signatures_url
    assert_response :success
  end

  test "should get new" do
    get new_e_signature_url
    assert_response :success
  end

  test "should create e_signature" do
    assert_difference("ESignature.count") do
      post e_signatures_url, params: { e_signature: { entity_id: @e_signature.entity_id, label: @e_signature.label, notes: @e_signature.notes, owner_id: @e_signature.owner_id, owner_type: @e_signature.owner_type, sequences: @e_signature.sequences, signature_type: @e_signature.signature_type, status: @e_signature.status, user_id: @e_signature.user_id } }
    end

    assert_redirected_to e_signature_url(ESignature.last)
  end

  test "should show e_signature" do
    get e_signature_url(@e_signature)
    assert_response :success
  end

  test "should get edit" do
    get edit_e_signature_url(@e_signature)
    assert_response :success
  end

  test "should update e_signature" do
    patch e_signature_url(@e_signature), params: { e_signature: { entity_id: @e_signature.entity_id, label: @e_signature.label, notes: @e_signature.notes, owner_id: @e_signature.owner_id, owner_type: @e_signature.owner_type, sequences: @e_signature.sequences, signature_type: @e_signature.signature_type, status: @e_signature.status, user_id: @e_signature.user_id } }
    assert_redirected_to e_signature_url(@e_signature)
  end

  test "should destroy e_signature" do
    assert_difference("ESignature.count", -1) do
      delete e_signature_url(@e_signature)
    end

    assert_redirected_to e_signatures_url
  end
end
