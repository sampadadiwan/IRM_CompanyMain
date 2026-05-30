class PortfolioReportDraftJob < ApplicationJob
  queue_as :low

  def perform(draft_id)
    draft   = PortfolioReportDraft.find(draft_id)
    user_id = draft.user_id

    Rails.logger.info { "[PortfolioReportDraftJob] Starting draft_id=#{draft_id}" }

    PortfolioReportDraftService.call(draft_id: draft_id, user_id: user_id)
  rescue StandardError => e
    Rails.logger.error { "[PortfolioReportDraftJob] Uncaught error for draft=#{draft_id}: #{e.message}" }
    send_notification("Report draft generation failed unexpectedly.", user_id, "danger")
    raise
  end
end
