class AddForumlaToAccountEntry < ActiveRecord::Migration[7.1]
  def change
    add_reference :account_entries, :fund_formula, null: true, foreign_key: true
    add_column :fund_formulas, :deleted_at, :datetime
    add_index :fund_formulas, :deleted_at
  end
end
