class InterestMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def notify_interest
    @interest = Interest.find params[:interest_id]
    send_mail(subject: "Interest received for #{@interest.secondary_sale.name} ")
  end

  def notify_shortlist
    @interest = Interest.find params[:interest_id]
    send_mail(subject: "Interest Shortlisted for #{@interest.secondary_sale.name} ")
  end

  def notify_accept_spa
    @interest = Interest.find params[:interest_id]
    send_mail(subject: "SPA confirmation received")
  end

  def notify_finalized
    @interest = Interest.find params[:interest_id]
    send_mail(subject: "Interest Finalized for #{@interest.secondary_sale.name} ")
  end
end
