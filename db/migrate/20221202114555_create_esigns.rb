class CreateEsigns < ActiveRecord::Migration[7.0]
  def change
    create_table :esigns do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :owner, polymorphic: true, null: false
      t.integer :sequence_no
      t.string :link
      t.text :reason
      t.string :status, limit: 100
      t.string :signature_type, :string, limit: 10
      t.boolean :completed, default: false

      t.timestamps
    end

  end
end
