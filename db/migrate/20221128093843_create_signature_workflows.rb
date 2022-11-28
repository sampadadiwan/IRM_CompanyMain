class CreateSignatureWorkflows < ActiveRecord::Migration[7.0]
  def change
    create_table :signature_workflows do |t|
      t.references :owner, polymorphic: true, null: false
      t.references :entity, null: false, foreign_key: true
      t.string :signatory_ids
      t.string :completed_ids
      t.string :state
      t.string :reason
      t.string :status
      t.boolean :sequential, default: false
      t.boolean :completed, default: false

      t.timestamps
    end
  end
end
