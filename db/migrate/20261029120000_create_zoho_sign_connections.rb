# A company's own Zoho Sign account (openspec/changes/zoho-esign-production-ready, design card ①),
# Zoho's per-signer id on e_signatures, and the documents.provider_doc_id index every eSign webhook
# looks documents up by.
class CreateZohoSignConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :zoho_sign_connections do |t|
      t.references :entity, null: false, foreign_key: true, index: { unique: true }
      t.string :region, limit: 10, null: false
      t.string :client_id, limit: 100, null: false
      # Encrypted (Active Record encryption) - text, since ciphertext is longer than the value
      t.text :client_secret, null: false
      t.text :refresh_token, null: false
      t.string :status, limit: 20, null: false, default: "connected"
      # The cutover: documents sent from this moment use this account
      t.datetime :connected_at, null: false
      t.datetime :last_verified_at
      t.datetime :last_webhook_at
      t.string :last_error
      t.string :webhook_token, limit: 40, null: false, index: { unique: true }
      t.text :webhook_secret, null: false
      t.datetime :webhook_secret_revealed_at
      t.references :connected_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_column :e_signatures, :provider_signer_id, :string, limit: 40
    # documents is large: build the index without blocking writes
    add_index :documents, :provider_doc_id, algorithm: :inplace
  end
end
