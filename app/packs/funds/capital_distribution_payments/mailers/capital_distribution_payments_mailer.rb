class CapitalDistributionPaymentsMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def send_notification
    @capital_distribution_payment = CapitalDistributionPayment.find params[:id]
    emails = sandbox_email(@capital_distribution_payment, @capital_distribution_payment.investor.emails)

    if emails.present?
      mail(from: from_email(@capital_distribution_payment.entity),
           to: emails,
           subject: "Capital Distribution: #{@capital_distribution_payment.entity.name}")
    end
  end
end
