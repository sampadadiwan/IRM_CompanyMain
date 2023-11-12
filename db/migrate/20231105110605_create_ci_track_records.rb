class CreateCiTrackRecords < ActiveRecord::Migration[7.1]
  def change
    create_table :ci_track_records do |t|
      t.references :ci_profile, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.string :name, limit: 50
      t.decimal :value, precision: 20, scale: 4
      t.string :prefix, limit: 5
      t.string :suffix, limit: 5
      t.string :details

      t.timestamps
    end
  end
end
