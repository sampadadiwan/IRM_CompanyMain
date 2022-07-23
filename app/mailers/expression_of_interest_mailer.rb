class ExpressionOfInterestMailer < ApplicationMailer
  helper EmailCurrencyHelper
  helper ApplicationHelper

  def notify_approved
    @expression_of_interest = ExpressionOfInterest.find(params[:id])

    # Get all emails of investors & holding company employees
    emails = @expression_of_interest.user.email

    mail(to: emails,
         bcc: ENV['SUPPORT_EMAIL'],
         subject: "Expression Of Interest received for: #{@expression_of_interest.investment_opportunity.company_name}")
  end
end
