class AddCreatedByToInvestorAdvisor < ActiveRecord::Migration[7.1]
  def change
    add_reference :investor_advisors, :created_by, null: true, foreign_key: { to_table: :users }
  end
end
