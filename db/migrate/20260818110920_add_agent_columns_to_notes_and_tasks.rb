# frozen_string_literal: true

# Adds traceability columns to notes and tasks so we can distinguish
# items created by the Deal Update Agent from manually created ones.
#
# These columns serve three purposes:
#   1. Audit — trace any note/task back to the original email
#   2. UI — show a "Created by agent" badge on the deal board
#   3. Analytics — filter/report on agent-created vs manual items
class AddAgentColumnsToNotesAndTasks < ActiveRecord::Migration[8.1]
  def change
    # --- Notes ---

    # Links the note back to the email that created it.
    # Enables "view original email" from the deal board.
    add_reference :notes, :source_email,
                  foreign_key: { to_table: :agent_ingested_emails },
                  null: true

    # Boolean flag for filtering and UI badges.
    # Default false — all existing notes are manual.
    add_column :notes, :created_by_agent, :boolean, default: false, null: false

    # Which matching tier was used (A in MVP, B/C/D/E in later phases).
    # Null for manually created notes.
    add_column :notes, :match_tier, :string, limit: 2

    # --- Tasks ---

    add_reference :tasks, :source_email,
                  foreign_key: { to_table: :agent_ingested_emails },
                  null: true

    add_column :tasks, :created_by_agent, :boolean, default: false, null: false

    add_column :tasks, :match_tier, :string, limit: 2
  end
end
