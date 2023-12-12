class CapitalDistributionPaymentsMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def send_notification
    @capital_distribution_payment = CapitalDistributionPayment.find params[:capital_distribution_payment_id]
    additional_ccs = @capital_distribution_payment.capital_commitment.cc
    subject = "Capital Distribution: #{@capital_distribution_payment.fund.name}"
    send_mail(subject:, additional_ccs:) if @to.present?
  end
end
