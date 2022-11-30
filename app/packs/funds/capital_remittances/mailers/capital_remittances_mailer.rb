class CapitalRemittancesMailer < ApplicationMailer
  helper EmailCurrencyHelper
  helper ApplicationHelper

  def send_notification
    @capital_remittance = CapitalRemittance.find params[:id]
    emails = sandbox_email(@capital_remittance, @capital_remittance.investor.emails)

    if emails.present?
      mail(from: from_email(@capital_remittance.entity),
           to: emails,
           subject: "Capital Call: #{@capital_remittance.entity.name}")
    end
  end
end
