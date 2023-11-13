class CreateCiWidgets < ActiveRecord::Migration[7.1]
  def change
    create_table :ci_widgets do |t|
      t.references :ci_profile, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.string :title
      t.text :details
      t.string :url
      t.string :image_placement, default: 'Left', limit: 6
      t.text :image_data
      t.timestamps
    end
  end
end
