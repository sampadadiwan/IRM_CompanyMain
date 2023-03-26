class AddTypeToCapitalDistribution < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_distributions, :commitment_type, :string, limit: 10, default: "Pool"
  end
end
