class CapitalDistributionPaymentsMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

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
