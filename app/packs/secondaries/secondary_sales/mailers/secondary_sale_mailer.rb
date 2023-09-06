class SecondarySaleMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def notify_open_for_interests
    @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
    send_mail(subject: "Secondary Sale: #{@secondary_sale.name} by #{@secondary_sale.entity.name}, open for interests")
  end

  def notify_closing_interests
    @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
    send_mail(subject: "Secondary Sale: #{@secondary_sale.name} by #{@secondary_sale.entity.name}, reminder to enter your interest")
  end

  def notify_open_for_offers
    @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
    send_mail(subject: "Secondary Sale: #{@secondary_sale.name} by #{@secondary_sale.entity.name}, open for offers")
  end

  def notify_closing_offers
    @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
    send_mail(subject: "Secondary Sale: #{@secondary_sale.name} by #{@secondary_sale.entity.name}, reminder to enter your offer")
  end

  def notify_allocation_offers
    @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
    send_mail(subject: "Secondary Sale: #{@secondary_sale.name} allocation complete.")
  end

  def notify_allocation_interests
    @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
    send_mail(subject: "Secondary Sale: #{@secondary_sale.name} allocation complete.")
  end

  def notify_spa_offers
    @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
    send_mail(subject: "Secondary Sale: #{@secondary_sale.name}, please accept uploaded SPA.")
  end

  def notify_spa_interests
    @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
    send_mail(subject: "Secondary Sale: #{@secondary_sale.name}, please accept uploaded SPA.")
  end
end
