class DocumentMailer < ApplicationMailer
  helper ApplicationHelper

  def notify_new_document
    @document = Document.find params[:id]
    @document.owner.access_rights

    email_list = @document.investor_users.collect(&:email)
    email_list += @document.owner.investor_users.collect(&:email) if @document.owner

    email = sandbox_email(@document, email_list.join(","))

    if email.present?
      subj = "New document #{@document.name} uploaded by #{@document.entity.name}"
      mail(from: from_email(@document.entity),
           to: ENV.fetch('SUPPORT_EMAIL', nil),
           cc: email,
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
