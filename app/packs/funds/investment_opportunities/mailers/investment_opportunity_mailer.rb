class InvestmentOpportunityMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def notify_open_for_interests
    @investment_opportunity = InvestmentOpportunity.find(params[:investment_opportunity_id])
    @user = User.find(params[:user_id])
    # Get all emails of investors & holding company employees
    emails = sandbox_email(@investment_opportunity,
                           @user.email)

    @entity = @investment_opportunity.entity
    cc = @entity.entity_setting.cc
    reply_to = cc

    mail(from: from_email(@investment_opportunity.entity),
         to: emails,
         reply_to:, cc:,
         subject: "Investment Opportunity: #{@investment_opportunity.company_name} by #{@investment_opportunity.entity.name}, open for interests")
  end

  def notify_allocation
    @investment_opportunity = InvestmentOpportunity.find(params[:investment_opportunity_id])
    @user = User.find(params[:user_id])

    @entity = @investment_opportunity.entity
    cc = @entity.entity_setting.cc
    reply_to = cc

    # Get all emails of investors & holding company employees
    emails = sandbox_email(@investment_opportunity,
                           @user.email)

    mail(from: from_email(@investment_opportunity.entity),
         to: emails,
         reply_to:, cc:,
         subject: "Investment Opportunity: #{@investment_opportunity.company_name} by #{@investment_opportunity.entity.name}, has been allocated")
  end
end
