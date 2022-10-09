require "test_helper"

class InvestorKycsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @investor_kyc = investor_kycs(:one)
  end

  test "should get index" do
    get investor_kycs_url
    assert_response :success
  end

  test "should get new" do
    get new_investor_kyc_url
    assert_response :success
  end

  test "should create investor_kyc" do
    assert_difference("InvestorKyc.count") do
      post investor_kycs_url, params: { investor_kyc: { PAN: @investor_kyc.PAN, address: @investor_kyc.address, bank_account_number: @investor_kyc.bank_account_number, bank_verification_response: @investor_kyc.bank_verification_response, bank_verification_status: @investor_kyc.bank_verification_status, bank_verified: @investor_kyc.bank_verified, comments: @investor_kyc.comments, entity_id: @investor_kyc.entity_id, first_name: @investor_kyc.first_name, ifsc_code: @investor_kyc.ifsc_code, investor_id: @investor_kyc.investor_id, last_name: @investor_kyc.last_name, middle_name: @investor_kyc.middle_name, pan_card_data: @investor_kyc.pan_card_data, pan_verification_response: @investor_kyc.pan_verification_response, pan_verification_status: @investor_kyc.pan_verification_status, pan_verified: @investor_kyc.pan_verified, signature_data: @investor_kyc.signature_data, user_id: @investor_kyc.user_id } }
    end

    assert_redirected_to investor_kyc_url(InvestorKyc.last)
  end

  test "should show investor_kyc" do
    get investor_kyc_url(@investor_kyc)
    assert_response :success
  end

  test "should get edit" do
    get edit_investor_kyc_url(@investor_kyc)
    assert_response :success
  end

  test "should update investor_kyc" do
    patch investor_kyc_url(@investor_kyc), params: { investor_kyc: { PAN: @investor_kyc.PAN, address: @investor_kyc.address, bank_account_number: @investor_kyc.bank_account_number, bank_verification_response: @investor_kyc.bank_verification_response, bank_verification_status: @investor_kyc.bank_verification_status, bank_verified: @investor_kyc.bank_verified, comments: @investor_kyc.comments, entity_id: @investor_kyc.entity_id, first_name: @investor_kyc.first_name, ifsc_code: @investor_kyc.ifsc_code, investor_id: @investor_kyc.investor_id, last_name: @investor_kyc.last_name, middle_name: @investor_kyc.middle_name, pan_card_data: @investor_kyc.pan_card_data, pan_verification_response: @investor_kyc.pan_verification_response, pan_verification_status: @investor_kyc.pan_verification_status, pan_verified: @investor_kyc.pan_verified, signature_data: @investor_kyc.signature_data, user_id: @investor_kyc.user_id } }
    assert_redirected_to investor_kyc_url(@investor_kyc)
  end

  test "should destroy investor_kyc" do
    assert_difference("InvestorKyc.count", -1) do
      delete investor_kyc_url(@investor_kyc)
    end

    assert_redirected_to investor_kycs_url
  end
end
