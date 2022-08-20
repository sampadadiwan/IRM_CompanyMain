require "test_helper"

class CapitalRemittancesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @capital_remittance = capital_remittances(:one)
  end

  test "should get index" do
    get capital_remittances_url
    assert_response :success
  end

  test "should get new" do
    get new_capital_remittance_url
    assert_response :success
  end

  test "should create capital_remittance" do
    assert_difference("CapitalRemittance.count") do
      post capital_remittances_url, params: { capital_remittance: { capital_call_id: @capital_remittance.capital_call_id, collected_amount: @capital_remittance.collected_amount, due_amount: @capital_remittance.due_amount, entity_id: @capital_remittance.entity_id, fund_id: @capital_remittance.fund_id, investor_id: @capital_remittance.investor_id, notes: @capital_remittance.notes, status: @capital_remittance.status } }
    end

    assert_redirected_to capital_remittance_url(CapitalRemittance.last)
  end

  test "should show capital_remittance" do
    get capital_remittance_url(@capital_remittance)
    assert_response :success
  end

  test "should get edit" do
    get edit_capital_remittance_url(@capital_remittance)
    assert_response :success
  end

  test "should update capital_remittance" do
    patch capital_remittance_url(@capital_remittance), params: { capital_remittance: { capital_call_id: @capital_remittance.capital_call_id, collected_amount: @capital_remittance.collected_amount, due_amount: @capital_remittance.due_amount, entity_id: @capital_remittance.entity_id, fund_id: @capital_remittance.fund_id, investor_id: @capital_remittance.investor_id, notes: @capital_remittance.notes, status: @capital_remittance.status } }
    assert_redirected_to capital_remittance_url(@capital_remittance)
  end

  test "should destroy capital_remittance" do
    assert_difference("CapitalRemittance.count", -1) do
      delete capital_remittance_url(@capital_remittance)
    end

    assert_redirected_to capital_remittances_url
  end
end
