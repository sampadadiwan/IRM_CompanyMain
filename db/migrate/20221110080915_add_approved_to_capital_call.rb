class AddApprovedToCapitalCall < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_calls, :approved, :boolean, default: false
    add_reference :capital_calls, :approved_by_user, null: true, foreign_key: { to_table: :users }
    add_column :capital_distributions, :approved, :boolean, default: false
    add_reference :capital_distributions, :approved_by_user, null: true, foreign_key: { to_table: :users }
  end
end
