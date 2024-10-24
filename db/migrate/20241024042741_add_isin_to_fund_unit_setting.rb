class AddIsinToFundUnitSetting < ActiveRecord::Migration[7.1]
  def change
    add_column :fund_unit_settings, :isin, :string, limit: 15
  end
end
