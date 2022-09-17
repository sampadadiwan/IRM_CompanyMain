require "test_helper"

class ShareTransfersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @share_transfer = share_transfers(:one)
  end

  test "should get index" do
    get share_transfers_url
    assert_response :success
  end

  test "should get new" do
    get new_share_transfer_url
    assert_response :success
  end

  test "should create share_transfer" do
    assert_difference("ShareTransfer.count") do
      post share_transfers_url, params: { share_transfer: { entity_id: @share_transfer.entity_id, from_investment_id: @share_transfer.from_investment_id, from_investor_id: @share_transfer.from_investor_id, from_user_id: @share_transfer.from_user_id, price: @share_transfer.price, quantity: @share_transfer.quantity, to_investment_id: @share_transfer.to_investment_id, to_investor_id: @share_transfer.to_investor_id, to_user_id: @share_transfer.to_user_id, transfer_date: @share_transfer.transfer_date, transfered_by_id: @share_transfer.transfered_by_id } }
    end

    assert_redirected_to share_transfer_url(ShareTransfer.last)
  end

  test "should show share_transfer" do
    get share_transfer_url(@share_transfer)
    assert_response :success
  end

  test "should get edit" do
    get edit_share_transfer_url(@share_transfer)
    assert_response :success
  end

  test "should update share_transfer" do
    patch share_transfer_url(@share_transfer), params: { share_transfer: { entity_id: @share_transfer.entity_id, from_investment_id: @share_transfer.from_investment_id, from_investor_id: @share_transfer.from_investor_id, from_user_id: @share_transfer.from_user_id, price: @share_transfer.price, quantity: @share_transfer.quantity, to_investment_id: @share_transfer.to_investment_id, to_investor_id: @share_transfer.to_investor_id, to_user_id: @share_transfer.to_user_id, transfer_date: @share_transfer.transfer_date, transfered_by_id: @share_transfer.transfered_by_id } }
    assert_redirected_to share_transfer_url(@share_transfer)
  end

  test "should destroy share_transfer" do
    assert_difference("ShareTransfer.count", -1) do
      delete share_transfer_url(@share_transfer)
    end

    assert_redirected_to share_transfers_url
  end
end
