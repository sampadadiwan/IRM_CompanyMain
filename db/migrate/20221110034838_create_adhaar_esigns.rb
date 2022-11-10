class CreateAdhaarEsigns < ActiveRecord::Migration[7.0]
  def change
    create_table :adhaar_esigns do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :document, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :esign_url
      t.string :esign_doc_id, limit: 20
      t.text :signed_file_url
      t.boolean :is_signed, default: false
      t.text :esign_document_reponse
      t.text :esign_retrieve_reponse

      t.timestamps
    end

    add_column :documents, :adhaar_esign_enabled, :boolean, default: false
    add_column :documents, :adhaar_esign_completed, :boolean, default: false
  end
end
