class ExpressionOfInterestMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def notify_approved
    @expression_of_interest = ExpressionOfInterest.find(params[:expression_of_interest_id])
    @user = User.find(params[:user_id])

    send_mail(subject: "Expression Of Interest received for: #{@expression_of_interest.investment_opportunity.company_name}")
  end
end
