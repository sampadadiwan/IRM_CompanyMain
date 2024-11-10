class FundUnitSettingDecorator < ApplicationDecorator
  delegate :name, to: :fund_unit_setting

  delegate :management_fee, to: :fund_unit_setting

  delegate :setup_fee, to: :fund_unit_setting

  delegate :carry, to: :fund_unit_setting

  delegate :isin, to: :fund_unit_setting
end
