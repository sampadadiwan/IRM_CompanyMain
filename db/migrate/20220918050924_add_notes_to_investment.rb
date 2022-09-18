class AddNotesToInvestment < ActiveRecord::Migration[7.0]
  def change
    add_column :investments, :notes, :text
  end
end
