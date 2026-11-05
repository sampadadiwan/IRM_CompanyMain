# Fund compliance monitoring — Phase 2: one AI draft of a check from a sentence ("Describe in words").
# Design: openspec/changes/fund-compliance-monitoring/design.md › compliance_check_drafts
# A new table only; no existing table is altered.
class CreateComplianceCheckDrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :compliance_check_drafts do |t|
      t.references :entity, null: true, foreign_key: true
      t.references :compliance_pack_version, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      # What was sent: the sentence (≤ 1,000 chars — E62, X39) and the field list (design › Record what was sent)
      t.text :sentence, null: false
      t.json :sent_context
      # The AI's structured draft (edited field by field) and its test run (preview — nothing stored)
      t.json :draft
      t.json :test_result
      t.bigint :test_fund_id
      t.string :status, limit: 10, null: false, default: "drafting"
      t.string :failure_reason, limit: 120
      t.string :saved_check_key, limit: 80
      t.timestamps
    end
  end
end
