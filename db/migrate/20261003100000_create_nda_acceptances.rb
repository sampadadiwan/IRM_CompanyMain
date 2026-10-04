# frozen_string_literal: true

# @description Creates the nda_acceptances table for tracking LP NDA accept/decline decisions.
#   Append-only audit trail — no updated_at, no unique constraint on [nda_config_id, user_id].
#   Multiple records per user/config pair are intentional (each action is a separate audit entry).
#
# @note Why append-only: Module 2 LP Acceptance Flow records every accept/decline
#   action with full audit metadata (IP, user agent, timestamps) for compliance.
class CreateNdaAcceptances < ActiveRecord::Migration[8.1]
  def change
    create_table :nda_acceptances do |t|
      t.bigint :nda_config_id, null: false
      t.bigint :user_id, null: false
      t.bigint :entity_id, null: false

      t.string :status, limit: 20, null: false
      t.integer :nda_version, null: false, default: 1

      t.string :ip_address, limit: 45
      t.string :user_agent, limit: 500

      t.datetime :accepted_at
      t.datetime :declined_at

      t.datetime :created_at, null: false
    end

    add_foreign_key :nda_acceptances, :nda_configs
    add_foreign_key :nda_acceptances, :users
    add_foreign_key :nda_acceptances, :entities

    change_table :nda_acceptances, bulk: true do |t|
      t.index %i[nda_config_id user_id created_at], name: "idx_nda_acceptances_gate_lookup"
      t.index :entity_id, name: "idx_nda_acceptances_entity"
      t.index :user_id, name: "idx_nda_acceptances_user"
    end
  end
end
