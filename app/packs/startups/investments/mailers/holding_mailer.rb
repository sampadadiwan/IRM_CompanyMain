class HoldingMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def notify_cancellation
    @holding = Holding.find params[:holding_id]

    @label = @holding.cancelled ? "Cancelled" : nil
    @label ||= @holding.lapsed ? "Lapsed" : "Updated"

    subject = "Your #{@holding.investment_instrument} have been #{@label}"
    send_mail(subject:)
  end

  def notify_approval
    @holding = Holding.find params[:holding_id]
    subject = "Your #{@holding.investment_instrument} have been approved"
    send_mail(subject:)
  end

  def notify_lapsed
    @holding = Holding.find params[:holding_id]
    subject = "Your #{@holding.investment_instrument} have lapsed"
    send_mail(subject:)
  end

  def notify_lapse_upcoming
    @holding = Holding.find params[:holding_id]
    subject = "Your #{@holding.investment_instrument} will lapse in #{@holding.days_to_lapse} days"
    send_mail(subject:)
  end
end
