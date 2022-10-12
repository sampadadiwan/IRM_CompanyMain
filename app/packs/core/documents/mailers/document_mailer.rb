class DocumentMailer < ApplicationMailer
  helper ApplicationHelper

  def notify_signature_required
    @access_right = AccessRight.find params[:access_right_id]
    @document = @access_right.owner

    email = sandbox_email(@document, @access_right.investor_emails)

    if email
      subj = "Signature required by #{@document.entity.name} for #{@document.name}"
      mail(from: from_email(@document.entity),
           to: email,
           cc: ENV['SUPPORT_EMAIL'],
           subject: subj)
    end
  end

  def notify_signed
    @document = Document.find params[:id]

    email = sandbox_email(@document, @document.signed_by.email)

    subj = "Signature for #{@document.name} needs to be accepted"
    mail(from: from_email(@document.entity),
         to: email,
         cc: ENV['SUPPORT_EMAIL'],
         subject: subj)
  end

  def notify_signed_accepted
    @document = Document.find params[:id]

    email = sandbox_email(@document, @document.signed_by.email)

    subj = "#{@document.name} has been accepted"
    mail(from: from_email(@document.entity),
         to: email,
         cc: ENV['SUPPORT_EMAIL'],
         subject: subj)
  end
end
