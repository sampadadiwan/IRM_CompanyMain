class AddFundCloseToCapitalCommitment < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_commitments, :fund_close, :string, limit: 15
    add_column :capital_calls, :fund_closes, :string, limit: 50

    CapitalCommitment.update_all(fund_close: "First Close")
  end
end
