class CapitalRemittanceMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  before_action :set_remittance
  def set_remittance
    @capital_remittance = CapitalRemittance.find params[:capital_remittance_id]
    @capital_call = @capital_remittance.capital_call
    @custom_notification = @capital_call.custom_notification(@notification.params[:email_method])
    @additional_ccs = @capital_remittance.capital_commitment.cc
  end

  def notify_capital_remittance
    subject = "#{@capital_remittance.fund.name}: #{@capital_remittance.capital_call.name}"
    # Check for attachments
    @capital_remittance.documents.generated.approved.each do |doc|
      # This password protects the file if required and attachs it
      pw_protect_attach_file(doc, @custom_notification)
    end

    @capital_remittance.documents.not_generated.each do |doc|
      # This attaches the file which is not generated
      attach_doc(doc)
    end

    send_mail(subject:)
  end

  def reminder_capital_remittance
    subject = "Reminder: #{@capital_remittance.fund.name}: #{@capital_remittance.capital_call.name}"

    # Check for attachments
    @capital_remittance.documents.generated.each do |doc|
      file = if @custom_notification&.password_protect_attachment
               password_protect_attachment(doc, @capital_remittance, @custom_notification)
             else
               doc.file
             end
      attachments["#{doc.name}.pdf"] = file.read
    end
    send_mail(subject:)
  end
end
