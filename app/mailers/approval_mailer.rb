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

  def notify_approval_response
    @approval_response = ApprovalResponse.find params[:id]
    # Get all emails of investors
    investor_emails = sandbox_email(@approval_response,
                                    @approval_response.investor.emails)

    employee_emails = sandbox_email(@approval_response,
                                    @approval_response.entity.employees.collect(&:email))

    mail(from: from_email(@approval_response.entity),
         to: investor_emails,
         cc: employee_emails,
         bcc: ENV['SUPPORT_EMAIL'],
         subject: "Approval response from #{@approval_response.investor.investor_name}: #{@approval_response.status} ")
  end
end
