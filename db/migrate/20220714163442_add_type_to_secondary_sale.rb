class AddTypeToSecondarySale < ActiveRecord::Migration[7.0]
  def change
    add_column :secondary_sales, :sale_type, :string, limit: 10, default: "Regular"
    add_column :offers, :auto_match, :boolean, default: true
    add_reference :interests, :funding_round, null: true, foreign_key: true
  end
end
