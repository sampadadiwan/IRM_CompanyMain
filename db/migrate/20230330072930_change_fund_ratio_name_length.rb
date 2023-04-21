class ChangeFundRatioNameLength < ActiveRecord::Migration[7.0]
  def change
    change_column :fund_ratios, :name, :string, limit: 255
    change_column :fund_ratios, :display_value, :string, limit: 50
  end
end
