class CreateComplianceRules < ActiveRecord::Migration[7.1]
  def change
    create_table :compliance_rules do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :for_class, limit: 20
      t.text :rule
      t.string :tags
      t.string :schedule, limit: 40

      t.timestamps
    end
  end
end
