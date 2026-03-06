class AddSectorToInvestors < ActiveRecord::Migration[8.0]
  def change
    add_column :investors, :sector, :string
  end
end
