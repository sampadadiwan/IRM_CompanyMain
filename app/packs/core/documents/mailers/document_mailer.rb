class DocumentMailer < ApplicationMailer
  helper ApplicationHelper

  def notify_new_document
    @document = Document.find params[:document_id]
    @user = User.find(params[:user_id])

    email_list = [@user.email]

    email = sandbox_email(@document, email_list.join(","))

    if email.present?
      subj = "New document #{@document.name} uploaded by #{@document.entity.name}"
      mail(from: from_email(@document.entity),
           to: email,
           cc: @document.entity.entity_setting.cc,
           reply_to: @document.entity.entity_setting.cc,
           subject: subj)
    else
      Rails.logger.debug { "No emails found for notify_new_document #{@document.name}" }
    end
  end

  def email_link
    @user = User.find(params[:user_id])
    @link = Document.find(params[:document_id]).file.url

    email = sandbox_email(@user, @user.email)

    if email.present?
      subj = "Download link"
      mail(from: from_email(@user.entity),
           to: email,
           subject: subj)
    end
  end
end
