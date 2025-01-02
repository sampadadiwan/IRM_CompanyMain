class RenameFeederFundFlag < ActiveRecord::Migration[7.2]
  def change
    rename_column :capital_commitments, :feeder_fund, :is_feeder_fund
  end
end
