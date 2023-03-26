class AddFolioToCapitalDistribution < ActiveRecord::Migration[7.0]
  def change
    add_reference :capital_distributions, :capital_commitment, null: true, foreign_key: true
    add_column :capital_distributions, :distribution_on, :integer, default: 0
  end
end
