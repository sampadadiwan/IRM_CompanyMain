class CapitalDistributionPaymentsMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def send_notification
    @capital_distribution_payment = CapitalDistributionPayment.find params[:capital_distribution_payment_id]

    send_mail(subject: "Capital Distribution: #{@capital_distribution_payment.entity.name}") if @to.present?
  end
end
