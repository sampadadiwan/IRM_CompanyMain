class InvestmentOpportunityMailer < ApplicationMailer
  helper EmailCurrencyHelper
  helper ApplicationHelper

  def notify_open_for_interests
    @investment_opportunity = InvestmentOpportunity.find(params[:id])

    # Get all emails of investors & holding company employees
    open_for_offers_emails = @investment_opportunity.access_rights.collect(&:investor_emails).flatten

    mail(to: ENV['SUPPORT_EMAIL'],
         bcc: open_for_offers_emails.join(','),
         subject: "Investment Opportunity: #{@investment_opportunity.company_name} by #{@investment_opportunity.entity.name}, open for interests")
  end

  def notify_allocation
    @investment_opportunity = InvestmentOpportunity.find(params[:id])

    # Get all emails of investors & holding company employees
    open_for_offers_emails = @investment_opportunity.access_rights.collect(&:investor_emails).flatten

    mail(to: ENV['SUPPORT_EMAIL'],
         bcc: open_for_offers_emails.join(','),
         subject: "Investment Opportunity: #{@investment_opportunity.company_name} by #{@investment_opportunity.entity.name}, has been allocated")
  end
end
