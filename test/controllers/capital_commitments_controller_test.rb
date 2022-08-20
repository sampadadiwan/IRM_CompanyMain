require "test_helper"

class CapitalCommitmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @capital_commitment = capital_commitments(:one)
  end

  test "should get index" do
    get capital_commitments_url
    assert_response :success
  end

  test "should get new" do
    get new_capital_commitment_url
    assert_response :success
  end

  test "should create capital_commitment" do
    assert_difference("CapitalCommitment.count") do
      post capital_commitments_url, params: { capital_commitment: { collected_amount: @capital_commitment.collected_amount, committed_amount: @capital_commitment.committed_amount, entity_id: @capital_commitment.entity_id, fund_id: @capital_commitment.fund_id, investor_id: @capital_commitment.investor_id, notes: @capital_commitment.notes } }
    end

    assert_redirected_to capital_commitment_url(CapitalCommitment.last)
  end

  test "should show capital_commitment" do
    get capital_commitment_url(@capital_commitment)
    assert_response :success
  end

  test "should get edit" do
    get edit_capital_commitment_url(@capital_commitment)
    assert_response :success
  end

  test "should update capital_commitment" do
    patch capital_commitment_url(@capital_commitment), params: { capital_commitment: { collected_amount: @capital_commitment.collected_amount, committed_amount: @capital_commitment.committed_amount, entity_id: @capital_commitment.entity_id, fund_id: @capital_commitment.fund_id, investor_id: @capital_commitment.investor_id, notes: @capital_commitment.notes } }
    assert_redirected_to capital_commitment_url(@capital_commitment)
  end

  test "should destroy capital_commitment" do
    assert_difference("CapitalCommitment.count", -1) do
      delete capital_commitment_url(@capital_commitment)
    end

    assert_redirected_to capital_commitments_url
  end
end
