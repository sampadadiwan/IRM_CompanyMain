class OfferMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  before_action :set_offer
  def set_offer
    @offer = Offer.find params[:offer_id]
    @secondary_sale = @offer.secondary_sale
    @custom_notification = CustomNotification.find(@notification.params[:custom_notification_id]) if @notification.params[:custom_notification_id].present?
  end

  def notify_approval
    subject = "Offer for #{@offer.secondary_sale.name} has been approved"
    send_mail(subject:)
  end

  def notify_accept_spa
    subject = "SPA confirmation received for #{@secondary_sale.name}"
    send_mail(subject:)
  end
end
