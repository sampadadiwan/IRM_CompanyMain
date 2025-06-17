class CreateDocShares < ActiveRecord::Migration[8.0]
  def change
    create_table :doc_shares do |t|
      t.string :email, null: false
      t.boolean :email_sent, default: false
      t.datetime :viewed_at
      t.integer :view_count, default: 0
      t.references :document, null: false, foreign_key: true

      t.timestamps
    end
    add_index :doc_shares, :email, unique: true
  end
end
