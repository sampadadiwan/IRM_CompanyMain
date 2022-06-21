class CreatePermissions < ActiveRecord::Migration[7.0]
  def change
    create_table :permissions do |t|
      t.references :user, null: true, foreign_key: true
      t.references :owner, polymorphic: true, null: false
      t.string :email
      t.integer :permissions
      t.references :entity, null: false, foreign_key: true
      t.references :granted_by, null: false, foreign_key: {to_table: :users}

      t.timestamps
    end
  end
end
