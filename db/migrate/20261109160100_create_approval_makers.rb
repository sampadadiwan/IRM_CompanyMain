# OWASP review 2026-11 M13 (openspec/changes/archive/2026-11-10-capital-call-distribution-maker-checker, design card ③, D2, LLD
# "Schema Detail").
#
# The preparer log: who created, imported or changed the figures of each capital call / distribution. Append-only
# (no updated_at): a row is written the first time a person prepares the record and never changed afterwards.
# The record's create-audit user also counts as a preparer (D4), so there is no backfill.
class CreateApprovalMakers < ActiveRecord::Migration[8.1]
  def change
    create_table :approval_makers do |t|
      # Tenant scope, copied from the record (never from params)
      t.references :entity, null: false, foreign_key: true
      # CapitalCall / CapitalDistribution — set from the model class, never from input
      t.string :approvable_type, limit: 40, null: false
      t.bigint :approvable_id, null: false
      # The preparer (the real person: CapHive support when acting as a user, D9)
      t.references :user, null: false, foreign_key: true
      # created / edited / imported — shown in the "Prepared by" tooltip; the approval rule ignores it
      t.string :role, limit: 20, null: false
      t.datetime :created_at, null: false
    end

    # One row per person per record: makes insert_all … unique_by idempotent (E8, E9)
    add_index :approval_makers, %i[approvable_type approvable_id user_id], unique: true,
                                                                           name: "index_approval_makers_on_approvable_and_user"
  end
end
