class AddFundingRoundToAggregateInvestment < ActiveRecord::Migration[7.0]
  def change
    add_reference :aggregate_investments, :funding_round, null: true, foreign_key: true
    add_column :aggregate_investments, :units, :integer, default: 0
    remove_column :entities, :units, :string
    add_column :entities, :units, :integer, default: 0
  end
end
