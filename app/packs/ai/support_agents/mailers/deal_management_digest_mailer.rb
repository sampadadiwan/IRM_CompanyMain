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
class DealManagementDigestMailer < SupportAgentBaseMailer
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

  # Sends a lightweight weekly summary email with key counts and
  # stagnation callouts. Links to the full weekly summary dashboard.
  #
  # @see DealManagementAgent#send_email_digest
  def weekly_summary
    @support_agent  = SupportAgent.find(params[:support_agent_id] || params["support_agent_id"])
    @deal           = Deal.find(params[:deal_id] || params["deal_id"])
    @notify_email   = params[:notify_email] || params["notify_email"]
    @period_deltas  = params[:period_deltas] || params["period_deltas"] || {}
    @stagnation     = params[:stagnation_breakdown] || params["stagnation_breakdown"] || {}
    @tasks_summary  = params[:tasks_summary] || params["tasks_summary"] || {}
    @weekly_insight = params[:weekly_insight] || params["weekly_insight"]
    @entity         = @support_agent.entity
    @run_at         = Time.current

    period_start = @period_deltas[:period_start] || @period_deltas["period_start"]
    @week_range = if period_start.present?
                    start_date = Time.parse(period_start.to_s)
                    "#{I18n.l(start_date.to_date, format: :short)} – #{I18n.l(@run_at.to_date, format: :short)}"
                  else
                    "Week of #{I18n.l(@run_at.to_date, format: :short)}"
                  end

    subject = "#{@deal.name} — Weekly Summary (#{@week_range})"

    mail(to: @notify_email, subject: subject)
  end
end
