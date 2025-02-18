class CreateViewedBies < ActiveRecord::Migration[7.2]
  def change
    create_table :viewed_bies do |t|
      t.references :owner, polymorphic: true, null: false
      t.references :user, null: true, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.integer :count, default: 0
      t.timestamps
    end
  end
end
