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
end
