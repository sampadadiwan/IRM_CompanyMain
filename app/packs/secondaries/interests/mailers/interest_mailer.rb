class InterestMailer < ApplicationMailer
  helper CurrencyHelper
  helper InterestsHelper
  helper ApplicationHelper

  before_action :set_interest
  def set_interest
    @interest = Interest.find params[:interest_id]
    @secondary_sale = @interest.secondary_sale
    @custom_notification = CustomNotification.find(@notification.params[:custom_notification_id]) if @notification.params[:custom_notification_id].present?
    @subject = @custom_notification&.subject || @notification.message
  end

  def notify_interest
    send_mail(subject: @subject)
  end

  def notify_shortlist
    send_mail(subject: @subject)
  end

  def notify_accept_spa
    send_mail(subject: "SPA confirmation received")
  end
end
