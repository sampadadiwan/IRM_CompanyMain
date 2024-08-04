class CapitalRemittancePaymentMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  before_action :set_remittance_payment
  def set_remittance_payment
    @capital_remittance_payment = CapitalRemittancePayment.find params[:capital_remittance_payment_id]
    @capital_remittance = @capital_remittance_payment.capital_remittance
    @capital_call = @capital_remittance.capital_call
    @custom_notification = @capital_call.custom_notification(@notification.params[:email_method])
    @additional_ccs = @capital_remittance.capital_commitment.cc
  end

  def notify_capital_remittance_payment
    subject = "Remittance payment received by #{@capital_remittance.fund.name} for #{@capital_remittance.capital_call.name}"
    send_mail(subject:)
  end
end
