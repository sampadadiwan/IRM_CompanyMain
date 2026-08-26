# frozen_string_literal: true

# Removes agent-specific columns from notes and tasks.
#
# The relationship between agent emails and the notes/tasks they create
# is now tracked from the agent side — agent_ingested_emails points to
# the created note/task via a polymorphic filed_as association. This
# keeps all agent data in the agent's own table and avoids cluttering
# core models with agent-specific columns.
class RemoveAgentColumnsFromNotesAndTasks < ActiveRecord::Migration[8.1]
  def change
    remove_reference :notes, :source_email, foreign_key: { to_table: :agent_ingested_emails }
    remove_column :notes, :created_by_agent, :boolean, default: false, null: false
    remove_column :notes, :match_tier, :string, limit: 2

    remove_reference :tasks, :source_email, foreign_key: { to_table: :agent_ingested_emails }
    remove_column :tasks, :created_by_agent, :boolean, default: false, null: false
    remove_column :tasks, :match_tier, :string, limit: 2
  end
end
