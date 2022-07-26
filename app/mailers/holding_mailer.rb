class HoldingMailer < ApplicationMailer
  helper EmailCurrencyHelper
  helper ApplicationHelper

  def notify_cancellation
    @holding = Holding.find params[:holding_id]
    emails = sandbox_email(@holding, @holding.user.email)

    @label = @holding.cancelled ? "Cancelled" : nil
    @label ||= @holding.lapsed ? "Lapsed" : "Updated"

    subject = "Your #{@holding.investment_instrument} have been #{@label}"
    mail(to: emails,
         cc: ENV['SUPPORT_EMAIL'],
         subject:)
  end

  def notify_approval
    @holding = Holding.find params[:holding_id]
    emails = sandbox_email(@holding, @holding.user.email)
    subject = "Your #{@holding.investment_instrument} have been approved"
    mail(to: emails,
         cc: ENV['SUPPORT_EMAIL'],
         subject:)
  end

  def notify_lapsed
    @holding = Holding.find params[:holding_id]
    emails = sandbox_email(@holding, @holding.user.email)
    subject = "Your #{@holding.investment_instrument} have lapsed"
    mail(to: emails,
         cc: ENV['SUPPORT_EMAIL'],
         subject:)
  end

  def notify_lapse_upcoming
    @holding = Holding.find params[:holding_id]
    emails = sandbox_email(@holding, @holding.user.email)
    subject = "Your #{@holding.investment_instrument} will lapse in #{@holding.days_to_lapse} days"
    mail(to: emails,
         cc: ENV['SUPPORT_EMAIL'],
         subject:)
  end
end
