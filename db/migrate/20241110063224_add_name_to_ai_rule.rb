class AddNameToAiRule < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_rules, :name, :string
  end
end
