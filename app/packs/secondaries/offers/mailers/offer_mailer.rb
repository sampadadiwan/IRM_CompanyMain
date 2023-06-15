class OfferMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def notify_approval
    @offer = Offer.find params[:offer_id]
    emails = sandbox_email(@offer, @offer.user.email)
    subject = "Your offer has been approved"
    cc = @offer.entity.entity_setting.cc
    reply_to = cc

    mail( from: from_email(@offer.entity), 
          to: emails, cc:, reply_to:,
          subject:)
  end

  def notify_accept_spa
    @offer = Offer.find params[:offer_id]
    sale = @offer.secondary_sale
    email_list = [@offer.user.email, sale.support_email].join(",")
    emails = sandbox_email(@offer, email_list)
    subject = "SPA confirmation received"
    cc = @offer.entity.entity_setting.cc
    reply_to = cc
    
    mail(from: from_email(@offer.entity), 
          to: emails, cc:, reply_to:,
          subject:)
  end
end
