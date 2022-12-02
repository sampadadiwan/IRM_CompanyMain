class SignatureWorkflowMailer < ApplicationMailer
  helper ApplicationHelper

  def notify_signature_required
    @esign = Esign.find params[:esign_id]
    email = sandbox_email(@esign, @esign.user.email)

    subj = @esign.reason
    mail(from: from_email(@esign.entity),
         to: email,
         subject: subj)
  end

  def notify_signature_completed
    @esign = Esign.find params[:esign_id]
    email = sandbox_email(@esign, @esign.user.email)

    subj = "Signature completed by user #{@esign.user.full_name} for #{@esign.entity.name} "
    mail(from: from_email(@esign.entity),
         to: email,
         subject: subj)
  end
end
