class AddEnabledToAiRule < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_rules, :enabled, :boolean, default: true
  end
end
