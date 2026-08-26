# frozen_string_literal: true

# Adds a polymorphic reference so agent_ingested_emails can point to
# the Note or Task it created. This is the reverse of the previous
# design where notes/tasks pointed back to agent_ingested_emails.
#
# Keeps all agent data in the agent's own table — core models (Note,
# Task) have zero knowledge of the agent system.
class AddFiledAsToAgentIngestedEmails < ActiveRecord::Migration[8.1]
  def change
    add_reference :agent_ingested_emails, :filed_as, polymorphic: true, null: true
  end
end
