class AddTypeToAiRule < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_rules, :rule_type, :string, limit: 15
    add_column :ai_checks, :rule_type, :string, limit: 15
  end
end
