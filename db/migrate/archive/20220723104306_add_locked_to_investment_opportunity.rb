class AddLockedToInvestmentOpportunity < ActiveRecord::Migration[7.0]
  def change
    add_column :investment_opportunities, :lock_allocations, :boolean, default: false
    add_column :investment_opportunities, :lock_eoi, :boolean, default: false
  end
end
