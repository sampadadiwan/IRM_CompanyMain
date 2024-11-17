class CreateAiChecks < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_checks do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :ai_rule, null: true, foreign_key: true
      t.references :parent, polymorphic: true, null: false
      t.references :owner, polymorphic: true, null: false
      t.string :status, limit: 5
      t.text :explanation
      t.json :audit_log

      t.timestamps
    end
  end
end
