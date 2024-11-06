class FundUnitSettingDecorator < ApplicationDecorator
  def name
    fund_unit_setting.name
  end

  def management_fee
    fund_unit_setting.management_fee
  end

  def setup_fee
    fund_unit_setting.setup_fee
  end

  def carry
    fund_unit_setting.carry
  end

  def isin
    fund_unit_setting.isin
  end
end
