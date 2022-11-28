class SignatureWorkflowMailer < ApplicationMailer
  helper ApplicationHelper

  def notify_signature_required
    @signature_workflow = SignatureWorkflow.find params[:id]
    @user = User.find params[:user_id]
    email = sandbox_email(@signature_workflow, @user.email)

    subj = @signature_workflow.reason
    mail(from: from_email(@signature_workflow.entity),
         to: email,
         cc: ENV['SUPPORT_EMAIL'],
         subject: subj)
  end

  def notify_signature_completed
    @signature_workflow = SignatureWorkflow.find params[:id]
    @user = User.find params[:user_id]
    email = sandbox_email(@signature_workflow, @user.email)

    subj = "Signature completed by user #{@user.full_name} for #{@signature_workflow.entity.name} "
    mail(from: from_email(@signature_workflow.entity),
         to: email,
         cc: ENV['SUPPORT_EMAIL'],
         subject: subj)
  end
end
