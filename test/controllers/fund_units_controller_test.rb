require "test_helper"

class FundUnitsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @fund_unit = fund_units(:one)
  end

  test "should get index" do
    get fund_units_url
    assert_response :success
  end

  test "should get new" do
    get new_fund_unit_url
    assert_response :success
  end

  test "should create fund_unit" do
    assert_difference("FundUnit.count") do
      post fund_units_url, params: { fund_unit: { capital_commitment_id: @fund_unit.capital_commitment_id, fund_id: @fund_unit.fund_id, investor_id: @fund_unit.investor_id, quantity: @fund_unit.quantity, reason: @fund_unit.reason, unit_type: @fund_unit.unit_type } }
    end

    assert_redirected_to fund_unit_url(FundUnit.last)
  end

  test "should show fund_unit" do
    get fund_unit_url(@fund_unit)
    assert_response :success
  end

  test "should get edit" do
    get edit_fund_unit_url(@fund_unit)
    assert_response :success
  end

  test "should update fund_unit" do
    patch fund_unit_url(@fund_unit), params: { fund_unit: { capital_commitment_id: @fund_unit.capital_commitment_id, fund_id: @fund_unit.fund_id, investor_id: @fund_unit.investor_id, quantity: @fund_unit.quantity, reason: @fund_unit.reason, unit_type: @fund_unit.unit_type } }
    assert_redirected_to fund_unit_url(@fund_unit)
  end

  test "should destroy fund_unit" do
    assert_difference("FundUnit.count", -1) do
      delete fund_unit_url(@fund_unit)
    end

    assert_redirected_to fund_units_url
  end
end
