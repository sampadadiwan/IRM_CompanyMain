class ChangeFundingRoundForFunds < ActiveRecord::Migration[7.0]
  def change
    change_column :funds, :funding_round_id, :bigint, null: true
    change_column :investment_opportunities, :funding_round_id, :bigint, null: true 
  end
end
