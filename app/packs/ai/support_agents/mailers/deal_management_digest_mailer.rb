# frozen_string_literal: true

# Sends a pipeline digest email after each DealManagementAgent run.
# When any :blocking issue exists, a blocker alert section is included.
# Invoked by DealManagementAgent#send_email_digest via deliver_later.
#
# Params:
#   support_agent_id  [Integer]
#   deal_id           [Integer]
#   notify_email      [String]
#   progress_issues   [Array<Hash>]
#   document_issues   [Array<Hash>]
#   extracted_terms   [Hash, nil]
#   score_leaderboard [Array<Hash>]
#   health_scores     [Hash]
#   has_blocking      [Boolean]
class DealManagementDigestMailer < ApplicationMailer
  def pipeline_digest
    @support_agent     = SupportAgent.find(params[:support_agent_id])
    @deal              = Deal.find(params[:deal_id])
    @notify_email      = params[:notify_email]
    @progress_issues   = Array(params[:progress_issues])
    @document_issues   = Array(params[:document_issues])
    @extracted_terms   = params[:extracted_terms]
    @score_leaderboard = Array(params[:score_leaderboard])
    @health_scores     = params[:health_scores] || {}
    @has_blocking      = params[:has_blocking]
    @entity            = @support_agent.entity
    @run_at            = Time.current

    prefix  = @has_blocking ? "[ALERT]" : "[Digest]"
    subject = "#{prefix} #{@deal.name} — Deal Management Report"

    mail(to: @notify_email, subject: subject)
  end
end
