class ChangeFundClosesLength < ActiveRecord::Migration[7.0]
  def change
    change_column :capital_calls, :fund_closes, :string, length: 100
    change_column :capital_commitments, :fund_close, :string, length: 30
  end
end
