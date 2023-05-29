class ExpressionOfInterestMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def notify_approved
    @expression_of_interest = ExpressionOfInterest.find(params[:id])

    # Get all emails of investors & holding company employees
    emails = sandbox_email(@expression_of_interest, @expression_of_interest.user.email)
    @entity = @expression_of_interest.entity
    cc = @entity.entity_setting.cc
    reply_to = cc

    mail(from: from_email(@expression_of_interest.entity),
         to: emails,
         reply_to:,
         cc:,
         subject: "Expression Of Interest received for: #{@expression_of_interest.investment_opportunity.company_name}")
  end
end
