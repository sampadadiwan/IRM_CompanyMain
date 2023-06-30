class AddPanToInvestor < ActiveRecord::Migration[7.0]
  def change
    add_column :investors, :pan, :string, limit: 15
  end
end
