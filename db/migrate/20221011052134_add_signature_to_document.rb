class AddSignatureToDocument < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :signature_enabled, :boolean, default: false
    add_reference :documents, :signed_by, null: true, foreign_key: { to_table: :users }
    add_reference :documents, :from_template, null: true, foreign_key: { to_table: :documents }
  end
end
