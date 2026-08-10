# frozen_string_literal: true

# Sends the Data Quality Agent health-score and fix-it report for a single fund.
# Recipients must be explicitly configured — no fallback to all entity employees.
# Respects the entity sandbox setting: when sandbox is ON, redirects to sandbox_emails.
#
# @see DataQualityAgent#send_quality_report
class DataQualityMailer < ApplicationMailer
  helper SupportAgentEmailHelper

  # @param support_agent [SupportAgent] agent record with json_fields["email"] recipients
  # @param fund [Fund] the fund this report covers
  # @param ctx [Hash] contains :check_results, :issues, :health_score
  def quality_report(support_agent, fund, ctx)
    @support_agent = support_agent
    @fund          = fund
    @check_results = ctx[:check_results]
    @issues        = ctx[:issues]
    @health_score  = ctx[:health_score]

    # Redirect to sandbox_emails when entity is in sandbox mode
    to = if fund.entity.entity_setting&.sandbox
           fund.entity.entity_setting.sandbox_emails
         else
           support_agent.json_fields["email"]
         end

    if to.blank?
      Rails.logger.info("[DataQualityMailer] No recipients for quality report (fund #{fund.id}) — skipping send")
      return
    end

    mail(to:, subject: "Data Quality Report — #{fund.name} (#{@health_score}%)")
  end
end
