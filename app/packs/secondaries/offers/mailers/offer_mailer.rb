class OfferMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def notify_approval
    @offer = Offer.find params[:offer_id]
    subject = "Offer for #{@offer.secondary_sale.name} has been approved"
    send_mail(subject:)
  end

  def notify_accept_spa
    @offer = Offer.find params[:offer_id]
    sale = @offer.secondary_sale
    subject = "SPA confirmation received for #{sale.name}"
    send_mail(subject:)
  end
end
