# frozen_string_literal: true

# Parking lot for emails the Deal Update Agent couldn't auto-file.
#
# An email lands here when:
#   - The LLM parsed intent as "unknown" (not a meeting note or task)
#   - The stakeholder string didn't match any DealInvestor with high confidence
#   - Multiple candidates matched and the agent can't pick one (Phase 2 disambiguation)
#
# The warehouse is the safety net — "if uncertain, warehouse, never guess."
# A team member reviews pending items on the deal page and manually files
# or discards them.
#
# Lifecycle:
#   - Created by ProcessDealIngestJob when auto-filing fails
#   - Sits with resolved_at = NULL until a user acts
#   - Resolved as "filed" (user picked the stakeholder, note/task created)
#     or "discarded" (irrelevant email, spam, etc.)
class CreateWarehouseItems < ActiveRecord::Migration[8.1]
  def change
    create_table :warehouse_items do |t|
      t.references :agent_ingested_email, null: false, foreign_key: true
      t.references :deal, null: false, foreign_key: true

      # What the LLM thought the intent was: meeting_note, task, or unknown.
      # Shown in the warehouse UI so the user has context before filing.
      t.string :parsed_intent, limit: 20

      # JSON array of DealInvestor IDs that were close but not confident
      # enough to auto-file. Phase 2 will use these for disambiguation
      # ("Did you mean 1. Sequoia or 2. SoftBank?"). Empty array in Phase 1
      # when zero candidates matched.
      t.json :candidate_stakeholder_ids

      # Null until a user manually resolves this item.
      t.datetime :resolved_at

      # The user who resolved it — audit trail.
      t.references :resolved_by, foreign_key: { to_table: :users }

      # "filed" = user picked a stakeholder and created the note/task.
      # "discarded" = user decided this email is irrelevant.
      t.string :resolution, limit: 20

      t.timestamps
    end

    # "Show me pending warehouse items for this deal" — the primary query
    # for the warehouse UI. resolved_at IS NULL = pending.
    add_index :warehouse_items, %i[deal_id resolved_at]
  end
end
