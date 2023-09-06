class CapitalRemittancesMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def send_notification
    @capital_remittance = CapitalRemittance.find params[:capital_remittance_id]

    # Check for attachments
    @capital_remittance.documents.generated.each do |doc|
      attachments["#{doc.name}.pdf"] = doc.file.read
    end

    send_mail(subject: "Capital Call: #{@capital_remittance.entity.name}") if @to.present?

    Chewy.strategy(:sidekiq) do
      @capital_remittance.notification_sent = true
      @capital_remittance.save
    end
  end

  def notify_capital_remittance
    @capital_remittance = CapitalRemittance.find(params[:capital_remittance_id])

    send_mail(subject: "New Capital Call by #{@capital_remittance.entity.name} : #{@capital_remittance.capital_call.name}") if @to.present?
  end

  def reminder_capital_remittance
    @capital_remittance = CapitalRemittance.find(params[:capital_remittance_id])
    send_mail(subject: "Reminder: Capital Call by #{@capital_remittance.entity.name} : #{@capital_remittance.capital_call.name}") if @to.present?
  end

  def payment_received
    @capital_remittance = CapitalRemittance.find(params[:capital_remittance_id])

    send_mail(subject: "Payment Received. #{@capital_remittance.entity.name} : #{@capital_remittance.capital_call.name}") if @to.present?
  end
end
