class CreateQuickLinkSteps < ActiveRecord::Migration[7.1]
  def change
    create_table :quick_link_steps do |t|
      t.string :name
      t.text :link
      t.text :description
      t.references :quick_link, null: false, foreign_key: true
      t.integer :position
      t.timestamps
    end
  end
end
