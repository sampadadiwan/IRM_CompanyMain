class ApprovalMailer < ApplicationMailer
  def notify_new_approval
    @approval = Approval.find params[:id]
    # Get all emails of investors
    investor_emails = sandbox_email(@approval,
                                    @approval.access_rights.collect(&:investor_emails).flatten)

    mail(from: from_email(@approval.entity),
         to: investor_emails,
         cc: ENV['SUPPORT_EMAIL'],
         subject: "Approval required by #{@approval.entity.name}: #{@approval.name} ")
  end
end
