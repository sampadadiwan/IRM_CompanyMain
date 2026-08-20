class CapitalRemittanceMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  PLACEHOLDERS = ApplicationMailer::PLACEHOLDERS.merge(
    "investor_name" => ->(m) { m.instance_variable_get(:@capital_remittance)&.investor&.name },
    "fund_name" => ->(m) { m.instance_variable_get(:@capital_remittance)&.fund&.name },
    "capital_call_name" => ->(m) { m.instance_variable_get(:@capital_call)&.name },
    "call_amount" => ->(m) { m.instance_variable_get(:@capital_remittance)&.call_amount&.format },
    "due_date" => ->(m) { (d = m.instance_variable_get(:@capital_call)&.due_date) && I18n.l(d, format: :email, locale: :en) },
    "kyc_full_name" => ->(m) { m.instance_variable_get(:@capital_remittance)&.capital_commitment&.investor_kyc&.full_name },
    "folio_id" => ->(m) { m.instance_variable_get(:@capital_remittance)&.folio_id },
    "committed_amount" => ->(m) { m.instance_variable_get(:@capital_remittance)&.capital_commitment&.committed_amount&.format },
    "remittance_amount" => ->(m) { m.instance_variable_get(:@capital_remittance)&.call_amount&.format }
  ).freeze

  before_action :set_remittance
  def set_remittance
    @capital_remittance = CapitalRemittance.find params[:capital_remittance_id]
    @capital_call = @capital_remittance.capital_call
    email_method = params[:email_method] || @notification.params[:email_method]
    @custom_notification = @capital_call.custom_notification(email_method)
    @additional_ccs = @capital_remittance.capital_commitment.cc
  end

  def notify_capital_remittance
    subject = "#{@capital_remittance.fund.name}: #{@capital_remittance.capital_call.name}"

    attach_all_files

    send_mail(subject:)
  end

  def reminder_capital_remittance
    subject = "Reminder: #{@capital_remittance.fund.name}: #{@capital_remittance.capital_call.name}"

    attach_all_files

    send_mail(subject:)
  end

  private

  def attach_all_files
    # Check for attachments
    @capital_remittance.documents.generated.approved.each do |doc|
      # This password protects the file if required and attachs it
      pw_protect_attach_file(doc, @custom_notification)
    end

    @capital_remittance.documents.not_generated.each do |doc|
      # This attaches the file which is not generated
      attach_doc(doc)
    end
  end
end
