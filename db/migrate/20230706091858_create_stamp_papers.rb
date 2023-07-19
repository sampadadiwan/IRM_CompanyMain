class CreateStampPapers < ActiveRecord::Migration[7.0]
  def change
    create_table :stamp_papers do |t|
      t.references :entity, null: false, foreign_key: true
      t.text :notes
      t.string :tags
      t.string :sign_on_page, limit: 5
      t.string :note_on_page, limit: 5
      t.references :owner, polymorphic: true, null: false

      t.timestamps
    end
  end
end
