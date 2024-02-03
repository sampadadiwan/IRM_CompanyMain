class AddUpdatedByToInvestorKyc < ActiveRecord::Migration[7.1]
  def change
    add_reference :investor_kycs, :investor_user, null: true, foreign_key: { to_table: :users }
    add_column :investor_kycs, :investor_user_updated_at, :datetime
  end
end
