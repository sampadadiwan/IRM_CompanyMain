class AddImportedToInvestor < ActiveRecord::Migration[7.0]
  def change
    add_column :investors, :imported, :boolean, default: false
  end
end
