class DocumentMailer < ApplicationMailer
  helper ApplicationHelper

  def notify_new_document
    @document = Document.find params[:document_id]

    if @to.present?
      subj = "#{@document.name} uploaded by #{@document.entity.name}"
      send_mail(subject: subj)
    else
      Rails.logger.debug { "No emails found for notify_new_document #{@document.name}" }
    end
  end

  def send_commitment_agreement
    @document = Document.find params[:document_id]
    @custom_notification = @document.entity.custom_notification("Commitment Agreement")
    subj = @custom_notification&.subject || "#{@document.name} uploaded by #{@document.entity.name}"

    # Check for attachments
    attachments["#{@document.name}.pdf"] = @document.file.read

    send_mail(subject: subj)
  end

  def email_link
    @link = Document.find(params[:document_id]).file.url

    if @to.present?
      subj = "Download link"
      send_mail(subject: subj)
    end
  end
end
