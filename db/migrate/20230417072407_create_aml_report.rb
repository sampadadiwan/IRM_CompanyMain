class CreateAmlReport < ActiveRecord::Migration[7.0]
  def change
    create_table :aml_reports do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :investor, null: false, foreign_key: true
      t.references :investor_kyc, null: false, foreign_key: true
      t.references :approved_by, null: true, foreign_key: {to_table: :users}
      t.string :name
      t.string :match_status
      t.boolean :approved, default: false
      t.string :types
      t.json :source_notes
      t.json :associates
      t.json :fields
      t.json :response

      t.timestamps
    end
  end
end
