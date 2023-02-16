class AddCumulativeToAccountEntry < ActiveRecord::Migration[7.0]
  def change
    add_column :account_entries, :cumulative, :boolean, default: false
    add_column :fund_formulas, :sequence, :integer, default: 0
  end
end
