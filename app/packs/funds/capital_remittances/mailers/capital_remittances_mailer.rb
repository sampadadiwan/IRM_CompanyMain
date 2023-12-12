class CapitalRemittancesMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def send_notification
    @capital_remittance = CapitalRemittance.find params[:capital_remittance_id]
    @capital_call = @capital_remittance.capital_call
    @custom_notification = @capital_call.custom_notification
    subject = @custom_notification&.subject || "#{@capital_remittance.fund.name}: #{@capital_remittance.capital_call.name}"

    # Check for attachments
    @capital_remittance.documents.generated.each do |doc|
      attachments["#{doc.name}.pdf"] = doc.file.read
    end
    send_mail(subject:) if @to.present?

    Chewy.strategy(:sidekiq) do
      @capital_remittance.notification_sent = true
      @capital_remittance.save
    end
  end

  def notify_capital_remittance
    @capital_remittance = CapitalRemittance.find(params[:capital_remittance_id])
    @capital_call = @capital_remittance.capital_call
    @custom_notification = @capital_call.custom_notification
    additional_ccs = @capital_remittance.capital_commitment.cc

    subject = @custom_notification&.subject || "#{@capital_remittance.fund.name}: #{@capital_remittance.capital_call.name}"

    send_mail(subject:, additional_ccs:) if @to.present?
  end

  def reminder_capital_remittance
    @capital_remittance = CapitalRemittance.find(params[:capital_remittance_id])
    @capital_call = @capital_remittance.capital_call
    @custom_notification = @capital_call.custom_notification

    subject = @custom_notification&.subject || "Reminder: #{@capital_remittance.fund.name}: #{@capital_remittance.capital_call.name}"

    # Check for attachments
    @capital_remittance.documents.generated.each do |doc|
      attachments["#{doc.name}.pdf"] = doc.file.read
    end
    send_mail(subject:) if @to.present?
  end

  def payment_received
    @capital_remittance = CapitalRemittance.find(params[:capital_remittance_id])
    subject = "Payment Confirmation for capital call #{@capital_remittance.fund.name}"
    send_mail(subject:) if @to.present?
  end

  def remittance_doc_errors
    setup_defaults
    @error_msg = params[:error_msg]
    mail(from: @from, to: @to, subject: "Remittance Documentation Generation Errors")
  end
end
