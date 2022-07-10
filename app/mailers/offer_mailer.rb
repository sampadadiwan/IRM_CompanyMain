class OfferMailer < ApplicationMailer
  helper EmailCurrencyHelper
  helper ApplicationHelper

  def notify_approval
    @offer = Offer.find params[:offer_id]
    emails = @offer.user.email
    subject = "Your offer has been approved"
    mail(to: emails,
         cc: ENV['SUPPORT_EMAIL'],
         subject:)
  end
end
