class CreateReports < ActiveRecord::Migration[7.1]
  def change
    create_table :reports do |t|
      t.references :entity, null: true, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.string :category, limit: 20
      t.text :description
      t.text :url

      t.timestamps
    end
  end
end
