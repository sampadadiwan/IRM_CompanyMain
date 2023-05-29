class InvestmentOpportunityMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def notify_open_for_interests
    @investment_opportunity = InvestmentOpportunity.find(params[:id])

    # Get all emails of investors & holding company employees
    open_for_offers_emails = sandbox_email(@investment_opportunity,
                                           @investment_opportunity.access_rights.collect(&:investor_emails).flatten)

    @entity = @investment_opportunity.entity
    cc = @entity.entity_setting.cc
    reply_to = cc

    mail(from: from_email(@investment_opportunity.entity), to: ENV.fetch('SUPPORT_EMAIL', nil),
         bcc: open_for_offers_emails.join(','),
         reply_to:, cc:,
         subject: "Investment Opportunity: #{@investment_opportunity.company_name} by #{@investment_opportunity.entity.name}, open for interests")
  end

  def notify_allocation
    @investment_opportunity = InvestmentOpportunity.find(params[:id])

    @entity = @investment_opportunity.entity
    cc = @entity.entity_setting.cc
    reply_to = cc

    # Get all emails of investors & holding company employees
    open_for_offers_emails = sandbox_email(@investment_opportunity,
                                           @investment_opportunity.access_rights.collect(&:investor_emails).flatten)

    mail(from: from_email(@investment_opportunity.entity), to: ENV.fetch('SUPPORT_EMAIL', nil),
         bcc: open_for_offers_emails.join(','), reply_to:, cc:,
         subject: "Investment Opportunity: #{@investment_opportunity.company_name} by #{@investment_opportunity.entity.name}, has been allocated")
  end
end
