class AddUnitsToFundingRound < ActiveRecord::Migration[7.0]
  def change
    add_column :funding_rounds, :units, :integer, default: 0
  end
end
