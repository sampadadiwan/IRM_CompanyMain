class FundMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def notify_capital_call
    @capital_call = CapitalCall.find(params[:id])

    # Get all emails of investors
    pending_investors = @capital_call.capital_remittances.pending.collect(&:investor)
    investor_emails = sandbox_email(@capital_call, pending_investors.collect(&:emails).flatten.join(','))

    mail(from: from_email(@capital_call.entity), to: ENV.fetch('SUPPORT_EMAIL', nil),
         bcc: investor_emails,
         subject: "New Capital Call by #{@capital_call.entity.name} : #{@capital_call.name}")
  end

  def reminder_capital_call
    @capital_call = CapitalCall.find(params[:id])

    # Get all emails of investors who have pending remittances
    pending_investors = @capital_call.capital_remittances.pending.collect(&:investor)
    investor_emails = sandbox_email(@capital_call, pending_investors.collect(&:emails).flatten.join(','))

    mail(from: from_email(@capital_call.entity),
         to: ENV.fetch('SUPPORT_EMAIL', nil),
         bcc: investor_emails,
         subject: "Reminder: Capital Call by #{@capital_call.entity.name} : #{@capital_call.name}")
  end
end
