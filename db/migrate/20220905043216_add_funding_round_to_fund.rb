class AddFundingRoundToFund < ActiveRecord::Migration[7.0]
  def change
    # add_reference :funds, :funding_round, null: false, foreign_key: true
    add_reference :investment_opportunities, :funding_round, null: false, foreign_key: true
  end
end
