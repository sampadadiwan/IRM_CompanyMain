class DocumentMailer < ApplicationMailer
  helper ApplicationHelper

  PLACEHOLDERS = ApplicationMailer::PLACEHOLDERS.merge(
    "document_name" => ->(m) { m.instance_variable_get(:@document)&.name },
    "kyc_full_name" => ->(m) { m.instance_variable_get(:@document)&.investor_kyc&.full_name },
    "folio_id" => ->(m) { m.instance_variable_get(:@document)&.capital_commitment&.folio_id },
    "committed_amount" => ->(m) { m.instance_variable_get(:@document)&.capital_commitment&.committed_amount&.format }
  ).freeze

  before_action :set_document
  def set_document
    @document = Document.find params[:document_id]
    @custom_notification = @document.entity.custom_notification(@notification.params[:email_method], custom_notification_id: @notification.params[:custom_notification_id])
  end

  def notify_new_document
    subject = "#{@document.name} uploaded by #{@document.entity.name}"
    send_mail(subject:)
  end

  def send_document
    subject = "#{@document.name} uploaded by #{@document.entity.name}"
    # This password protects the file if required and attachs it
    pw_protect_attach_file(@document, @custom_notification)
    send_mail(subject:)
  end

  def email_link
    # Link will expire in 1 week
    @link = @document.file.url(expires_in: (60 * 60 * 24 * 7), response_content_disposition: "inline; filename=#{@document.name_with_extension}")
    @msg = params[:msg]
    subject = "Download link"
    send_mail(subject:)
  end
end
