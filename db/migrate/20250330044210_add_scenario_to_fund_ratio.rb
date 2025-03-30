class AddScenarioToFundRatio < ActiveRecord::Migration[8.0]
  def change
    add_column :fund_ratios, :scenario, :string, limit: 40, default: "Default"    
  end
end
