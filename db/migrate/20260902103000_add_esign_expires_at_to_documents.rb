class AddEsignExpiresAtToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :esign_expires_at, :datetime, if_not_exists: true
  end
end
