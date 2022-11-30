class AddManualGenerationToCapitalRemittances < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_calls, :manual_generation, :boolean, default: false
    add_column :capital_distributions, :manual_generation, :boolean, default: false
  end
end
