class CreateInvestmentCriteriaTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :investment_criteria_templates do |t|
      t.string :name, null: false
      t.json :criteria, null: false
      t.references :created_by_user, null: false, foreign_key: { to_table: :users }
      t.integer :usage_count, default: 0, null: false
      t.timestamps
    end
  end
end
