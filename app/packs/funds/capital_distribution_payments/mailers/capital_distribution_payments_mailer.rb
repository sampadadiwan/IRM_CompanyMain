class CapitalDistributionPaymentsMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def send_notification
    @capital_distribution_payment = CapitalDistributionPayment.find params[:capital_distribution_payment_id]
    subject = "Capital Distribution: #{@capital_distribution_payment.fund.name}"
    send_mail(subject:)
  end
end
