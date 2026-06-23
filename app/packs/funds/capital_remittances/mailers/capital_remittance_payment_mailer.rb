class CapitalRemittancePaymentMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  PLACEHOLDERS = ApplicationMailer::PLACEHOLDERS.merge(
    "investor_name" => ->(m) { m.instance_variable_get(:@capital_remittance)&.investor&.name },
    "fund_name" => ->(m) { m.instance_variable_get(:@capital_remittance)&.fund&.name },
    "capital_call_name" => ->(m) { m.instance_variable_get(:@capital_call)&.name },
    "payment_amount" => ->(m) { m.instance_variable_get(:@capital_remittance_payment)&.amount&.format },
    "kyc_full_name" => ->(m) { m.instance_variable_get(:@capital_remittance)&.capital_commitment&.investor_kyc&.full_name },
    "folio_id" => ->(m) { m.instance_variable_get(:@capital_remittance)&.folio_id },
    "committed_amount" => ->(m) { m.instance_variable_get(:@capital_remittance)&.capital_commitment&.committed_amount&.format },
    "remittance_amount" => ->(m) { m.instance_variable_get(:@capital_remittance)&.call_amount&.format }
  ).freeze

  before_action :set_remittance_payment
  def set_remittance_payment
    @capital_remittance_payment = CapitalRemittancePayment.find params[:capital_remittance_payment_id]
    @capital_remittance = @capital_remittance_payment.capital_remittance
    @capital_call = @capital_remittance.capital_call
    email_method = params[:email_method] || @notification.params[:email_method]
    @custom_notification = @capital_call.custom_notification(email_method)
    @additional_ccs = @capital_remittance.capital_commitment.cc
  end

  def notify_capital_remittance_payment
    subject = "Remittance payment received by #{@capital_remittance.fund.name} for #{@capital_remittance.capital_call.name}"
    send_mail(subject:)
  end
end
