class AddInvestorNameToExpressionOfInterest < ActiveRecord::Migration[7.1]
  def change
    add_column :expression_of_interests, :investor_name, :string, limit: 100
    add_column :investment_opportunities, :shareable, :boolean, default: false
  end
end
