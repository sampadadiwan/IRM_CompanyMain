require "test_helper"

class FundRatiosControllerTest < ActionDispatch::IntegrationTest
  setup do
    @fund_ratio = fund_ratios(:one)
  end

  test "should get index" do
    get fund_ratios_url
    assert_response :success
  end

  test "should get new" do
    get new_fund_ratio_url
    assert_response :success
  end

  test "should create fund_ratio" do
    assert_difference("FundRatio.count") do
      post fund_ratios_url, params: { fund_ratio: { display_value: @fund_ratio.display_value, entity_id: @fund_ratio.entity_id, fund_id: @fund_ratio.fund_id, name: @fund_ratio.name, notes: @fund_ratio.notes, valuation_id: @fund_ratio.valuation_id, value: @fund_ratio.value } }
    end

    assert_redirected_to fund_ratio_url(FundRatio.last)
  end

  test "should show fund_ratio" do
    get fund_ratio_url(@fund_ratio)
    assert_response :success
  end

  test "should get edit" do
    get edit_fund_ratio_url(@fund_ratio)
    assert_response :success
  end

  test "should update fund_ratio" do
    patch fund_ratio_url(@fund_ratio), params: { fund_ratio: { display_value: @fund_ratio.display_value, entity_id: @fund_ratio.entity_id, fund_id: @fund_ratio.fund_id, name: @fund_ratio.name, notes: @fund_ratio.notes, valuation_id: @fund_ratio.valuation_id, value: @fund_ratio.value } }
    assert_redirected_to fund_ratio_url(@fund_ratio)
  end

  test "should destroy fund_ratio" do
    assert_difference("FundRatio.count", -1) do
      delete fund_ratio_url(@fund_ratio)
    end

    assert_redirected_to fund_ratios_url
  end
end
