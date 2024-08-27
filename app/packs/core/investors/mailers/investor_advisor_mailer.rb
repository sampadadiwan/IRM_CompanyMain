class InvestorAdvisorMailer < ApplicationMailer
  helper ApplicationHelper

  def notify_investor_advisor_addition
    @investor_advisor = InvestorAdvisor.find params[:investor_advisor_id]
    @owner_name = params[:owner_name]
    subject = "Investor Advisor #{@investor_advisor.user.full_name} has been added"
    send_mail(subject:)
  end
end
