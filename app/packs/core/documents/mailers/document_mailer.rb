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

  def email_link
    @user = User.find(params[:user_id])
    @link = params[:link]

    email = sandbox_email(@user, @user.email)

    if email.present?
      subj = "Download link"
      mail(from: from_email(@user.entity),
           to: email,
           subject: subj)
    end
  end
end
