class CapitalDistributionPaymentsMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  PLACEHOLDERS = ApplicationMailer::PLACEHOLDERS.merge(
    "investor_name" => ->(m) { m.instance_variable_get(:@capital_distribution_payment)&.investor&.name },
    "fund_name" => ->(m) { m.instance_variable_get(:@capital_distribution_payment)&.fund&.name },
    "net_payable_amount" => ->(m) { m.instance_variable_get(:@capital_distribution_payment)&.net_payable&.format },
    "kyc_full_name" => ->(m) { m.instance_variable_get(:@capital_distribution_payment)&.capital_commitment&.investor_kyc&.full_name },
    "folio_id" => ->(m) { m.instance_variable_get(:@capital_distribution_payment)&.folio_id },
    "committed_amount" => ->(m) { m.instance_variable_get(:@capital_distribution_payment)&.capital_commitment&.committed_amount&.format }
  ).freeze

  before_action :set_dist_payment
  def set_dist_payment
    @capital_distribution_payment = CapitalDistributionPayment.find params[:capital_distribution_payment_id]
    email_method = params[:email_method] || @notification.params[:email_method]
    @custom_notification = @capital_distribution_payment.capital_distribution.custom_notification(email_method)
    @additional_ccs = @capital_distribution_payment.capital_commitment&.cc
  end

  def send_notification
    subject = "Capital Distribution: #{@capital_distribution_payment.fund.name}"
    attach_all_files
    send_mail(subject:)
  end

  private

  def attach_all_files
    # Check for attachments
    @capital_distribution_payment.documents.generated.approved.each do |doc|
      # This password protects the file if required and attachs it
      pw_protect_attach_file(doc, @custom_notification)
    end

    @capital_distribution_payment.documents.not_generated.each do |doc|
      # This attaches the file which is not generated
      attach_doc(doc)
    end
  end
end
