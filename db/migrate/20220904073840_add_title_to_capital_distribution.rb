class AddTitleToCapitalDistribution < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_distributions, :title, :string
    add_column :capital_distributions, :completed, :boolean, default: false
    add_column :capital_distribution_payments, :completed, :boolean, default: false    
  end
end
