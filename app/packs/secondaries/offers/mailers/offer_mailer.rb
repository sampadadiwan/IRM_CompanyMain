class OfferMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def notify_approval
    @offer = Offer.find params[:offer_id]
    @user = User.find params[:user_id]
    emails = sandbox_email(@offer, @user.email)
    subject = "Offer for #{@offer.secondary_sale.name} has been approved"
    cc = @offer.entity.entity_setting.cc
    reply_to = cc

    mail(from: from_email(@offer.entity),
         to: emails, cc:, reply_to:,
         subject:)
  end

  def notify_accept_spa
    @offer = Offer.find params[:offer_id]
    @user = User.find params[:user_id]
    sale = @offer.secondary_sale
    email_list = [@user.email, sale.support_email].join(",")
    emails = sandbox_email(@offer, email_list)
    subject = "SPA confirmation received for #{sale.name}"
    cc = @offer.entity.entity_setting.cc
    reply_to = cc

    mail(from: from_email(@offer.entity),
         to: emails, cc:, reply_to:,
         subject:)
  end
end
