class CreateVideoKycs < ActiveRecord::Migration[7.0]
  def change
    create_table :video_kycs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :investor_kyc, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true

      t.timestamps
    end
  end
end
