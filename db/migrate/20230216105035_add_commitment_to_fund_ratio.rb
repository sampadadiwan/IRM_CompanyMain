class AddCommitmentToFundRatio < ActiveRecord::Migration[7.0]
  def change
    add_reference :fund_ratios, :capital_commitment, null: true, foreign_key: true
  end
end
