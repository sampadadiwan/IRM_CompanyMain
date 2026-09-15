# frozen_string_literal: true

# Stores Shrine file references for email attachments on AgentIngestedEmail.
# Attachments are uploaded synchronously during webhook processing and
# associated with the created Task by DealIngestProcessor.
class AddAttachmentDataToAgentIngestedEmails < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_ingested_emails, :attachment_data, :json, default: nil
  end
end
