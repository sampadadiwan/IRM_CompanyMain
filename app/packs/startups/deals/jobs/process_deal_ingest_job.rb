# frozen_string_literal: true

# Async processing of an authenticated deal ingest email.
#
# Enqueued by DealIngestAuthenticator after all auth checks pass.
# Calls DealIngestProcessor to parse the email via LLM, match the
# stakeholder, and create a Note/Task or warehouse the email.
#
# Runs in Sidekiq's default queue. Each email is processed independently.
#
# @see DealIngestAuthenticator for the auth layer that enqueues this
# @see DealIngestProcessor for the orchestrator (Step 6)
class ProcessDealIngestJob < ApplicationJob
  queue_as :default

  # Skip retries if the email record was deleted between enqueue and execution.
  discard_on ActiveRecord::RecordNotFound

  # @param ingested_email_id [Integer] the AgentIngestedEmail record ID
  def perform(ingested_email_id)
    # Chewy requires an explicit indexing strategy in Sidekiq jobs.
    Chewy.strategy(:atomic) do
      DealIngestProcessor.call(ingested_email_id)
    end
  end
end
