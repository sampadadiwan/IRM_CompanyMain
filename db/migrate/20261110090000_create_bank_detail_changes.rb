# M14 (OWASP review 2026-11) — one row per bank change of a KYC: maker, masked before/after, second-person state and
# once-only email stamps (openspec/changes/bank-detail-change-controls, design D6, LLD "Schema Detail").
# Additive: a new table, no backfill, no lock on an existing table.
class CreateBankDetailChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :bank_detail_changes do |t|
      # Tenant scope; the [entity_id, status] index below serves the firm-wide payout lookups
      t.references :entity, null: false, foreign_key: true, index: false
      # The KYC; [investor_kyc_id, status] serves "the awaiting change of this KYC"
      t.references :investor_kyc, null: false, foreign_key: true, index: false
      # The maker; nil = System (a job with nobody behind it)
      t.references :changed_by, foreign_key: { to_table: :users }
      # investor / fund / system — investor-made changes are confirmable by any approver
      t.string :changed_by_side, limit: 10, null: false
      # screen, api, import, document_checks, ai_extraction, other
      t.string :source, limit: 20, null: false, default: "other"
      # The payout columns changed (comma list), for the email wording
      t.string :changed_fields, limit: 100, null: false
      # Masked: last 4 only; nil = blank
      t.string :old_account_last4, limit: 4
      t.string :new_account_last4, limit: 4
      # IFSC is a public branch code: kept in full (same limit as investor_kycs.ifsc_code)
      t.string :old_ifsc, limit: 20
      t.string :new_ifsc, limit: 20
      # Changed payout custom fields [{key, label, kind, old, new}], written from Phase 6 (D19)
      t.json :changed_custom_fields
      t.string :status, limit: 12, null: false, default: "awaiting"
      t.references :confirmed_by, foreign_key: { to_table: :users }
      t.datetime :confirmed_at
      # Confirmed by the maker because the firm has no other KYC approver who can see the KYC (D7)
      t.boolean :only_approver, null: false, default: false
      # Once-only claims for the two emails (D9) and who the investor email went to
      t.datetime :investor_notified_at
      t.text :investor_recipient_ids
      t.datetime :approvers_notified_at
      # Trackable → acts_as_paranoid
      t.datetime :deleted_at, index: true
      t.timestamps
      # "the awaiting change of this KYC" (every KYC page and policy check); payout lookups per firm
      t.index %i[investor_kyc_id status]
      t.index %i[entity_id status]
    end
  end
end
