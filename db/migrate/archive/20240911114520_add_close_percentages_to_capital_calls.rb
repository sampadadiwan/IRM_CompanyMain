class AddClosePercentagesToCapitalCalls < ActiveRecord::Migration[7.1]
  def change
    add_column :capital_calls, :close_percentages, :json
  end
end
