# frozen_string_literal: true

# @description Creates the nda_configs table with polymorphic owner association.
#   NdaConfig belongs_to :owner (polymorphic) — any model (Folder,
#   InvestmentOpportunity, etc.) can have an NDA configuration.
#
# Changed: Fresh create (not a rename from folder_nda_configs).
# Why: Clean migration for the polymorphic NdaConfig design per PR #1750 review.
class CreateNdaConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :nda_configs do |t|
      # Polymorphic owner (Folder, InvestmentOpportunity, etc.)
      t.string :owner_type, null: false
      t.bigint :owner_id, null: false

      t.bigint :entity_id, null: false
      t.boolean :enabled, default: true, null: false

      # NDA document (Shrine JSON)
      t.text :nda_document_data

      # Acceptance method: click_through or e_sign
      t.string :acceptance_method, limit: 20, default: "click_through", null: false

      # Validity settings
      t.string :validity_type, limit: 20, default: "until_revoked", null: false
      t.integer :validity_days
      t.date :validity_date

      # Notifications
      t.string :contact_email
      t.text :notification_emails

      # Versioning
      t.integer :version, default: 1, null: false

      # Audit
      t.bigint :created_by_id
      t.bigint :updated_by_id
      t.datetime :deleted_at

      t.timestamps
    end

    # One NDA config per owner
    add_index :nda_configs, %i[owner_type owner_id], unique: true, name: "idx_nda_configs_owner_uniq"
    add_index :nda_configs, :entity_id
    add_index :nda_configs, :created_by_id
    add_index :nda_configs, :updated_by_id
    add_index :nda_configs, :deleted_at, name: "idx_nda_configs_deleted_at"
  end
end
