class CreateQuickLinks < ActiveRecord::Migration[7.1]
  def change
    create_table :quick_links do |t|
      t.string :name
      t.text :description
      t.string :tags
      t.references :entity, null: true, foreign_key: true

      t.timestamps
    end
  end
end
