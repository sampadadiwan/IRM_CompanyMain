class AddFormulaToOptionPool < ActiveRecord::Migration[7.0]
  def change
    add_column :option_pools, :formula, :text
  end
end
