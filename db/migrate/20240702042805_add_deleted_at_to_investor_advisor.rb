class AddDeletedAtToInvestorAdvisor < ActiveRecord::Migration[7.1]
  def change
    add_column :investor_advisors, :deleted_at, :datetime
    add_index :investor_advisors, :deleted_at
  end
end
