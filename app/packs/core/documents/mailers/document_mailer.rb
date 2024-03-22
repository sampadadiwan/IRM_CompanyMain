class DocumentMailer < ApplicationMailer
  helper ApplicationHelper

  before_action :set_document
  def set_document
    @document = Document.find params[:document_id]
    @custom_notification = @document.entity.custom_notification(@notification.params[:email_method])
  end

  def notify_new_document
    subject = "#{@document.name} uploaded by #{@document.entity.name}"
    send_mail(subject:)
  end

  def send_commitment_agreement
    subject = "#{@document.name} uploaded by #{@document.entity.name}"
    # This password protects the file if required and attachs it
    pw_protect_attach_file(@document, @custom_notification)
    send_mail(subject:)
  end

  def email_link
    @link = @document.file.url
    subject = "Download link"
    send_mail(subject:)
  end
end
