class CreateIncomingEmails < ActiveRecord::Migration[7.1]
  def change
    create_table :incoming_emails do |t|
      t.string :from
      t.string :to
      t.string :subject
      t.text :body
      t.references :owner, polymorphic: true, null: true
      t.references :entity, null: true, foreign_key: true

      t.timestamps
    end
  end
end
