class FundMailer < ApplicationMailer
  helper EmailCurrencyHelper
  helper ApplicationHelper

  def notify_capital_call
    @capital_call = CapitalCall.find(params[:id])

    # Get all emails of investors
    investor_emails = sandbox_email(@capital_call,
                                    @capital_call.fund.access_rights.collect(&:investor_emails).flatten.join(','))

    mail(from: from_email(@capital_call.entity), to: ENV['SUPPORT_EMAIL'],
         bcc: investor_emails,
         subject: "Capital Call by #{@capital_call.entity.name} : #{@capital_call.name}")
  end

  def reminder_capital_call
    @capital_call = CapitalCall.find(params[:id])

    # Get all emails of investors who have pending remittances
    pending_investors = @capital_call.capital_remittances.pending.collect(&:investor)
    investor_emails = sandbox_email(@capital_call, pending_investors.collect(&:emails).flatten.join(','))

    mail(from: from_email(@capital_call.entity),
         to: ENV['SUPPORT_EMAIL'],
         bcc: investor_emails,
         subject: "Capital Call by #{@capital_call.entity.name} : #{@capital_call.name}")
  end
end
