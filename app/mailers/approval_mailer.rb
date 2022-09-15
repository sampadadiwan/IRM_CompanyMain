class ApprovalMailer < ApplicationMailer
  helper ApplicationHelper

  def notify_new_approval
    @approval = Approval.find params[:id]

    if @approval.approved
      if params[:access_right_id].present?
        # Get all emails of investor
        access_right = AccessRight.find(params[:access_right_id])
        investor_emails = sandbox_email(@approval,
                                        access_right.investor_emails.flatten.join(","))
      else
        # Get all emails of investors
        investor_emails = sandbox_email(@approval,
                                        @approval.pending_investors.collect(&:emails).flatten.join(","))
      end

      logger.debug "from email = #{from_email(@approval.entity)} #{ENV['SUPPORT_EMAIL']}"

      mail(from: from_email(@approval.entity),
           to: investor_emails,
           cc: ENV['SUPPORT_EMAIL'],
           subject: "Approval required by #{@approval.entity.name}: #{@approval.title}")

    else
      logger.debug "Not sending approval mail as approval is not yet approved."
    end
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
