class InvestorAdvisorMailer < ApplicationMailer
  helper ApplicationHelper

  def notify_investor_advisor_addition
    @investor = Investor.find(params[:investor_id])
    @import_upload = ImportUpload.find(params[:import_upload_id])
    @investor_advisor = InvestorAdvisor.find params[:investor_advisor_id]
    @fund_name = params[:fund_name]
    subject = "Investor Advisor #{@investor_advisor.user.first_name} #{@investor_advisor.user.last_name} has been added"
    send_mail(subject:)
  end
end
