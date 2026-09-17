# frozen_string_literal: true

# Sends a validation summary email to the FM who triggered the run.
#
# Called after PortfolioCompanyAgent.process_batch completes (adhoc runs only,
# not scheduled). Aggregates batch results into a dashboard-style summary:
# total companies, up-to-date vs issues, per-category breakdown.
#
# Follows the same pattern as DealManagementDigestMailer — inherits from
# SupportAgentBaseMailer for shared email helpers (sa_banner, sa_callout, etc.).
#
# @see PortfolioCompanyAgent.send_validation_summary
# @see DealManagementDigestMailer
class PortfolioValidationDigestMailer < SupportAgentBaseMailer
  # Sends the post-run validation summary email.
  #
  # @param support_agent_id [Integer] the PortfolioCompanyAgent's SupportAgent record
  # @param user_id [Integer] the FM who triggered the run
  # @param successes [Array<Hash>] successfully processed companies ({id:, name:})
  # @param errors [Array<Hash>] failed companies ({target_id:, target_name:, error:})
  # @param summary [Hash] aggregated stats from reports (:total, :up_to_date,
  #   :has_issues, :kpi_overdue, :valuation_overdue, :documents_overdue, :period_label)
  def validation_summary
    @support_agent = SupportAgent.find(params[:support_agent_id])
    @user          = User.find(params[:user_id])
    @successes     = Array(params[:successes])
    @errors        = Array(params[:errors])
    @summary       = params[:summary] || {}
    @entity        = @support_agent.entity
    @run_at        = Time.current

    total       = @summary[:total] || (@successes.size + @errors.size)
    has_issues  = (@summary[:has_issues] || 0).positive?
    prefix      = has_issues ? "[Alert]" : "[Summary]"

    subject = "#{prefix} Portfolio Validation — #{total} companies checked"

    # Use @to (set by ApplicationMailer#setup_defaults) which respects
    # entity sandbox setting — redirects to sandbox_emails when enabled.
    mail(to: @to, subject: subject)
  end
end
