class AddPrefConversionToInvestment < ActiveRecord::Migration[7.0]
  def change
    add_column :investments, :preferred_conversion, :integer
  end
end
