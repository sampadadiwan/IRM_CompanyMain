class AddCashFlowsToFundRatio < ActiveRecord::Migration[7.0]
  def change
    add_column :fund_ratios, :cash_flows, :json
  end
end
