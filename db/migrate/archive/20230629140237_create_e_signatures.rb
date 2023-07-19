class CreateESignatures < ActiveRecord::Migration[7.0]
  def change
    create_table :e_signatures do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.string :label, limit: 20
      t.string :signature_type, limit: 10
      t.integer :position
      t.references :owner, polymorphic: true, null: false
      t.text :notes
      t.string :status, limit: 10

      t.timestamps
    end
  end
end
