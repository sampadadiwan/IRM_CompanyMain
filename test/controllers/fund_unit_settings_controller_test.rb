require "test_helper"

class FundUnitSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @fund_unit_setting = fund_unit_settings(:one)
  end

  test "should get index" do
    get fund_unit_settings_url
    assert_response :success
  end

  test "should get new" do
    get new_fund_unit_setting_url
    assert_response :success
  end

  test "should create fund_unit_setting" do
    assert_difference("FundUnitSetting.count") do
      post fund_unit_settings_url, params: { fund_unit_setting: { entity_id: @fund_unit_setting.entity_id, fund_id: @fund_unit_setting.fund_id, management_fee: @fund_unit_setting.management_fee, name: @fund_unit_setting.name, setup_fee: @fund_unit_setting.setup_fee } }
    end

    assert_redirected_to fund_unit_setting_url(FundUnitSetting.last)
  end

  test "should show fund_unit_setting" do
    get fund_unit_setting_url(@fund_unit_setting)
    assert_response :success
  end

  test "should get edit" do
    get edit_fund_unit_setting_url(@fund_unit_setting)
    assert_response :success
  end

  test "should update fund_unit_setting" do
    patch fund_unit_setting_url(@fund_unit_setting), params: { fund_unit_setting: { entity_id: @fund_unit_setting.entity_id, fund_id: @fund_unit_setting.fund_id, management_fee: @fund_unit_setting.management_fee, name: @fund_unit_setting.name, setup_fee: @fund_unit_setting.setup_fee } }
    assert_redirected_to fund_unit_setting_url(@fund_unit_setting)
  end

  test "should destroy fund_unit_setting" do
    assert_difference("FundUnitSetting.count", -1) do
      delete fund_unit_setting_url(@fund_unit_setting)
    end

    assert_redirected_to fund_unit_settings_url
  end
end
