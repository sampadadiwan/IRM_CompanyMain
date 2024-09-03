class InterestMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  before_action :set_interest
  def set_interest
    @interest = Interest.find params[:interest_id]
    @secondary_sale = @interest.secondary_sale
    @custom_notification = CustomNotification.find(@notification.params[:custom_notification_id]) if @notification.params[:custom_notification_id].present?
  end

  def notify_interest
    send_mail(subject: "Interest received for #{@interest.secondary_sale.name} ")
  end

  def notify_shortlist
    send_mail(subject: "Interest Shortlisted for #{@interest.secondary_sale.name} ")
  end

  def notify_accept_spa
    send_mail(subject: "SPA confirmation received")
  end
end
