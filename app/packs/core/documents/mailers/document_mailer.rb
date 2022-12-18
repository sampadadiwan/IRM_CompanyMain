class DocumentMailer < ApplicationMailer
  helper ApplicationHelper

  def notify_new_document
    @document = Document.find params[:id]
    @document.owner.access_rights

    email = sandbox_email(@document, @document.investor_users.collect(&:email).join(","))

    if email.present?
      subj = "New document #{@document.name} uploaded by #{@document.entity.name}"
      mail(from: from_email(@document.entity),
           to: email,
           subject: subj)
    end
  end
end
