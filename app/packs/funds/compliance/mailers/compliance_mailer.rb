# ⑨ Compliance emails: single notices and the daily digest. Dates go through bare l(...) so
# EmailDateLocalization renders "Mon dd, yyyy" (CLAUDE.md).
class ComplianceMailer < ApplicationMailer
  helper EmailStyleHelper
  helper ApplicationHelper

  def notice
    @message = params[:message]
    @lines = Array(params[:lines])
    send_mail(subject: "Compliance — #{@message.to_s.truncate(80)}")
  end

  def digest
    @as_of = params[:as_of].present? ? Date.parse(params[:as_of].to_s) : Time.zone.today
    @message = params[:message]
    @lines = Array(params[:lines])
    send_mail(subject: "Compliance digest — #{@message}")
  end

  # X28: a failed run also alerts CapHive support at SUPPORT_EMAIL_TO (set per env in .env.*), the
  # same mailbox EntityMailer uses. Only ids, names, the date and the error class go out — no
  # investor data (Security › minimum PII). Skipped when the address is not configured.
  def run_failed_support
    to = ENV.fetch("SUPPORT_EMAIL_TO", nil)
    return if to.blank?

    @run = ComplianceRun.find(params[:run_id])
    @entity = @run.entity
    @fund = @run.fund
    mail(to:, subject: "Compliance run failed — #{@entity.name} / #{@fund.name} on #{I18n.l(@run.run_date, format: :email, locale: :en)}")
  end
end
