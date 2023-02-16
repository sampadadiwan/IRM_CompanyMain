require "application_system_test_case"

class FundUnitSettingsTest < ApplicationSystemTestCase
  setup do
    @fund_unit_setting = fund_unit_settings(:one)
  end

  test "visiting the index" do
    visit fund_unit_settings_url
    assert_selector "h1", text: "Fund unit settings"
  end

  test "should create fund unit setting" do
    visit fund_unit_settings_url
    click_on "New fund unit setting"

    fill_in "Entity", with: @fund_unit_setting.entity_id
    fill_in "Fund", with: @fund_unit_setting.fund_id
    fill_in "Management fee", with: @fund_unit_setting.management_fee
    fill_in "Name", with: @fund_unit_setting.name
    fill_in "Setup fee", with: @fund_unit_setting.setup_fee
    click_on "Create Fund unit setting"

    assert_text "Fund unit setting was successfully created"
    click_on "Back"
  end

  test "should update Fund unit setting" do
    visit fund_unit_setting_url(@fund_unit_setting)
    click_on "Edit this fund unit setting", match: :first

    fill_in "Entity", with: @fund_unit_setting.entity_id
    fill_in "Fund", with: @fund_unit_setting.fund_id
    fill_in "Management fee", with: @fund_unit_setting.management_fee
    fill_in "Name", with: @fund_unit_setting.name
    fill_in "Setup fee", with: @fund_unit_setting.setup_fee
    click_on "Update Fund unit setting"

    assert_text "Fund unit setting was successfully updated"
    click_on "Back"
  end

  test "should destroy Fund unit setting" do
    visit fund_unit_setting_url(@fund_unit_setting)
    click_on "Destroy this fund unit setting", match: :first

    assert_text "Fund unit setting was successfully destroyed"
  end
end
