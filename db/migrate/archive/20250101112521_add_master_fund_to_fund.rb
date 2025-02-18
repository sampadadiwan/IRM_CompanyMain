class AddMasterFundToFund < ActiveRecord::Migration[7.2]
  def change
    add_reference :funds, :master_fund, null: true, foreign_key: { to_table: :funds }
    add_reference :capital_commitments, :feeder_fund, null: true, foreign_key: { to_table: :funds }
  end
end
