# Fund compliance monitoring — Phase 1 tables.
# Design: openspec/changes/fund-compliance-monitoring/design.md › Data model and schema changes
# Every table is new; no existing table is altered (LLD › Migration safety).
class CreateCompliancePhase1Tables < ActiveRecord::Migration[8.1]
  def change
    # ① A rulebook — CapHive-owned (entity_id NULL) or an entity's own fund-agreement pack
    create_table :compliance_packs do |t|
      t.references :entity, null: true, foreign_key: true
      t.string :name, limit: 120, null: false
      t.string :regime, limit: 30, null: false, default: "SEBI"
      t.boolean :locked, null: false, default: false
      t.string :time_zone, limit: 50, null: false, default: "Asia/Kolkata"
      t.date :retired_on
      t.timestamps
    end

    # ① Immutable-once-published definitions over time
    create_table :compliance_pack_versions do |t|
      t.references :compliance_pack, null: false, foreign_key: true
      t.integer :version_no, null: false
      t.date :effective_from
      t.string :status, limit: 10, null: false, default: "draft"
      t.bigint :corrects_version_id
      t.string :applicability, limit: 12, null: false, default: "all"
      t.date :applicability_date
      t.date :transition_ends_on
      t.boolean :allows_early_adoption, null: false, default: false
      t.json :definition
      t.datetime :tested_at
      t.bigint :tested_by_id
      t.string :counsel_reviewer, limit: 120
      t.date :counsel_reviewed_on
      t.bigint :published_by_id
      t.datetime :published_at
      t.timestamps
    end
    add_index :compliance_pack_versions, %i[compliance_pack_id version_no], unique: true, name: "idx_cpv_pack_version"

    # ② A pack attached to a fund, with the fund's classification and current version
    create_table :fund_compliance_packs do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.references :compliance_pack, null: false, foreign_key: true
      t.string :classification, limit: 40
      t.references :compliance_pack_version, null: true, foreign_key: true
      t.string :status, limit: 10, null: false, default: "active"
      t.date :attached_on
      t.timestamps
    end
    add_index :fund_compliance_packs, %i[fund_id compliance_pack_id], unique: true, name: "idx_fcp_fund_pack"

    # ② One setup per entity: input mappings, dated reference lists, owner, AI settings, monitoring switch
    create_table :compliance_entity_setups do |t|
      t.references :entity, null: false, foreign_key: true, index: { unique: true }
      t.json :input_mappings
      t.json :reference_lists
      t.bigint :owner_id
      t.json :ai_settings
      t.boolean :monitoring_enabled, null: false, default: false
      t.date :monitoring_since
      # Local time zone for the 02:00 run and 08:00 digest (E29); effective dates use the pack's zone (R18)
      t.string :time_zone, limit: 50, null: false, default: "Asia/Kolkata"
      t.date :last_digest_on
      # One-off lines for the next digest (version notices, dropped overrides, reassignments)
      t.json :digest_notes
      t.timestamps
    end

    # ⑦ Maker–checker requests (override / disable / detach / explanation / early adoption / classification)
    create_table :compliance_requests do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :kind, limit: 20, null: false
      t.string :target_type, limit: 40, null: false
      t.bigint :target_id, null: false
      t.string :check_key, limit: 80
      t.json :payload
      t.text :reason
      t.string :status, limit: 12, null: false, default: "pending"
      t.boolean :self_approved, null: false, default: false
      t.bigint :requested_by_id, null: false
      t.bigint :decided_by_id
      t.datetime :decided_at
      t.text :decision_note
      t.timestamps
    end
    add_index :compliance_requests, %i[target_type target_id status], name: "idx_creq_target_status"

    # ⑤ One run of one fund
    create_table :compliance_runs do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.date :run_date, null: false
      t.string :trigger, limit: 10, null: false, default: "nightly"
      t.string :status, limit: 10, null: false, default: "running"
      t.datetime :finished_at
      t.text :error_summary
      t.timestamps
    end
    add_index :compliance_runs, %i[fund_id run_date trigger], name: "idx_crun_fund_date_trigger"

    # ⑤ Append-only check outcomes
    create_table :compliance_results do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :compliance_run, null: false, foreign_key: true
      t.references :fund_compliance_pack, null: false, foreign_key: true
      t.bigint :compliance_pack_version_id, null: false
      t.string :check_key, limit: 80, null: false
      t.string :subject_type, limit: 40
      t.bigint :subject_id
      t.string :outcome, limit: 16, null: false
      t.decimal :figure, precision: 20, scale: 4
      t.decimal :limit_value, precision: 20, scale: 4
      t.json :working
      t.string :superseded_reason, limit: 20
      t.timestamps
    end
    # rubocop:disable-next Rails/BulkChangeTable -- indexes on a brand-new table
    add_index :compliance_results, %i[fund_compliance_pack_id check_key id], name: "idx_cres_pack_check_id"
    add_index :compliance_results, %i[check_key subject_type subject_id], name: "idx_cres_subject"

    # ⑥ One breach episode; open_key "1" while open, NULL when closed → one open item per check
    create_table :compliance_register_items do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.references :fund_compliance_pack, null: false, foreign_key: true
      t.string :check_key, limit: 80, null: false
      t.string :status, limit: 16, null: false, default: "open"
      t.bigint :first_result_id
      t.bigint :last_result_id
      t.date :opened_on
      t.date :fix_by
      t.bigint :assignee_id
      t.decimal :approved_figure, precision: 20, scale: 4
      t.string :closed_reason, limit: 16
      t.date :closed_on
      t.string :open_key, limit: 1
      t.boolean :reopened_worse, null: false, default: false
      t.date :escalated_on
      t.timestamps
    end
    # rubocop:disable-next Rails/BulkChangeTable -- indexes on a brand-new table
    add_index :compliance_register_items, %i[fund_compliance_pack_id check_key open_key], unique: true, name: "idx_creg_open_item"
    add_index :compliance_register_items, %i[entity_id status], name: "idx_creg_entity_status"

    # ⑥ One occurrence of a manual duty; subject '' / 0 for scheduled duties so the unique key holds
    create_table :compliance_duties do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund_compliance_pack, null: false, foreign_key: true
      t.string :duty_key, limit: 80, null: false
      t.string :period_key, limit: 20, null: false, default: ""
      t.string :subject_type, limit: 40, null: false, default: ""
      t.bigint :subject_id, null: false, default: 0
      t.date :period_end
      t.date :due_on
      t.bigint :owner_id
      t.bigint :done_by_id
      t.date :done_on
      t.text :note
      t.text :ai_notes
      t.bigint :document_folder_id
      t.timestamps
    end
    add_index :compliance_duties, %i[fund_compliance_pack_id duty_key period_key subject_type subject_id], unique: true, name: "idx_cduty_unique"

    # ⑦ Wet-ink sign-off of an uploaded document (one per document)
    create_table :document_signoffs do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :document, null: false, foreign_key: true, index: { unique: true }
      t.date :signed_on, null: false
      t.bigint :marked_by_id, null: false
      t.timestamps
    end
  end
end
