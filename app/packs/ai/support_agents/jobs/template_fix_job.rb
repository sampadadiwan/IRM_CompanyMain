# frozen_string_literal: true

# Background job for the "Fix Me" button on a template Document.
#
# Exists as a dedicated job — rather than routing through the generic
# SupportAgentJob — because it needs to pass agent-specific params
# (issue_description, llm_model) into the Trailblazer ctx, the same reason
# PortfolioValidationJob exists instead of extending SupportAgentJob. Keeps
# the shared support_agents framework files untouched.
#
# @see TemplateFixAgent
# @see DocumentsController#run_fix
class TemplateFixJob < ApplicationJob
  queue_as :agents

  # @param support_agent_id [Integer] the TemplateFixAgent's SupportAgent record ID
  # @param document_id [Integer] the template Document to fix
  # @param issue_description [String] the user's free-text description of the problem
  # @param llm_model [String, nil] model id chosen in the Fix Me modal; nil uses the agent's default
  # @param user_id [Integer] the user who triggered the run
  def perform(support_agent_id:, document_id:, issue_description:, user_id:, llm_model: nil)
    support_agent = SupportAgent.find(support_agent_id)
    document = Document.find(document_id)

    # Document has a Chewy update_index callback (app/packs/core/documents/models/document.rb),
    # which raises Chewy::UndefinedUpdateStrategy outside an active strategy — TemplateFixAgent's
    # finalize_fix step saves the fixed draft as a new Document (DocxWorkspace#
    # save_as_new_document!), which needs a strategy context here the same way
    # CapitalCommitmentDocJob#perform wraps its own Document-creating work.
    Chewy.strategy(:sidekiq) do
      report = TemplateFixAgent.new.initialize_report_with_steps(
        {}, model: document, support_agent: support_agent, user_id: user_id
      )

      TemplateFixAgent.call(
        support_agent_id: support_agent_id,
        document: document,
        issue_description: issue_description,
        llm_model: llm_model,
        user_id: user_id,
        entity_id: support_agent.entity_id,
        support_agent_report: report
      )
    end

    message = "Template Fix Agent finished for '#{document.name}'. " \
              "<a href='#{Rails.application.routes.url_helpers.document_path(document, tab: 'fix_me')}' " \
              "class='text-decoration-underline'>View result</a>"
    send_notification(message, user_id, "success")
  rescue StandardError => e
    Rails.logger.error { "[TemplateFixJob] error for Document ID=#{document_id}: #{e.message}" }
    Rails.logger.error { e.backtrace.join("\n") }
    send_notification("Template Fix Agent failed for Document ID=#{document_id}: #{e.message}", user_id, "danger")
    raise
  end
end
