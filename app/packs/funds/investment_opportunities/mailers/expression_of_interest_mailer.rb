class ExpressionOfInterestMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def notify_approved
    @expression_of_interest = ExpressionOfInterest.find(params[:id])

    # Get all emails of investors & holding company employees
    emails = sandbox_email(@expression_of_interest, @expression_of_interest.user.email)

    mail(from: from_email(@expression_of_interest.entity),
         to: emails,
         subject: "Expression Of Interest received for: #{@expression_of_interest.investment_opportunity.company_name}")
  end
end
