class AddSubjectToAgentIngestedEmails < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_ingested_emails, :subject, :string
  end
end
