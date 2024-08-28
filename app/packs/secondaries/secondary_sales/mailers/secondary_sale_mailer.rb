class SecondarySaleMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  before_action :set_secondary_sale
  def set_secondary_sale
    @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
    @custom_notification = @secondary_sale.custom_notification(@notification.params[:email_method])
  end

  def notify_open_for_interests
    send_mail(subject: "Secondary Sale: #{@secondary_sale.name} by #{@secondary_sale.entity.name}, open for interests")
  end

  def notify_closing_interests
    send_mail(subject: "Secondary Sale: #{@secondary_sale.name} by #{@secondary_sale.entity.name}, reminder to enter your interest")
  end

  def notify_open_for_offers
    send_mail(subject: "Secondary Sale: #{@secondary_sale.name} by #{@secondary_sale.entity.name}, open for offers")
  end

  def notify_closing_offers
    send_mail(subject: "Secondary Sale: #{@secondary_sale.name} by #{@secondary_sale.entity.name}, reminder to enter your offer")
  end

  def notify_allocation_offers
    send_mail(subject: "Secondary Sale: #{@secondary_sale.name} allocation complete.")
  end

  def notify_allocation_interests
    send_mail(subject: "Secondary Sale: #{@secondary_sale.name} allocation complete.")
  end

  def notify_spa_offers
    send_mail(subject: "Secondary Sale: #{@secondary_sale.name}, please accept uploaded SPA.")
  end

  def notify_spa_interests
    send_mail(subject: "Secondary Sale: #{@secondary_sale.name}, please accept uploaded SPA.")
  end

  def adhoc_notification
    send_mail(subject: @custom_notification.subject, template_path: 'application_mailer', template_name: 'adhoc_notification')
  end
end
