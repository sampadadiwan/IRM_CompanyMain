class SecondarySaleMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def notify_open_for_interests
    @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
    email = User.find(params[:user_id]).email

    mail(from: from_email(@secondary_sale.entity), to: sandbox_email(@secondary_sale, email),
         cc: @secondary_sale.entity.entity_setting.cc,
         subject: "Secondary Sale: #{@secondary_sale.name} by #{@secondary_sale.entity.name}, open for interests")
  end

  def notify_closing_interests
    @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
    email = User.find(params[:user_id]).email

    mail(from: from_email(@secondary_sale.entity), to: sandbox_email(@secondary_sale, email),
         cc: @secondary_sale.entity.entity_setting.cc,
         subject: "Secondary Sale: #{@secondary_sale.name} by #{@secondary_sale.entity.name}, reminder to enter your interest")
  end

  def notify_open_for_offers
    @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
    email = User.find(params[:user_id]).email

    mail(from: from_email(@secondary_sale.entity),
         to: sandbox_email(@secondary_sale, email),
         cc: @secondary_sale.entity.entity_setting.cc,
         subject: "Secondary Sale: #{@secondary_sale.name} by #{@secondary_sale.entity.name}, open for offers")
  end

  def notify_closing_offers
    @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
    email = User.find(params[:user_id]).email

    mail(from: from_email(@secondary_sale.entity),
         to: sandbox_email(@secondary_sale, email),
         cc: @secondary_sale.entity.entity_setting.cc,
         subject: "Secondary Sale: #{@secondary_sale.name} by #{@secondary_sale.entity.name}, reminder to enter your offer")
  end

  def notify_allocation_offers
    @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
    email = User.find(params[:user_id]).email

    mail(from: from_email(@secondary_sale.entity),
         to: sandbox_email(@secondary_sale, email),
         cc: @secondary_sale.entity.entity_setting.cc,
         subject: "Secondary Sale: #{@secondary_sale.name} allocation complete.")
  end

  def notify_allocation_interests
    @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
    email = User.find(params[:user_id]).email

    mail(from: from_email(@secondary_sale.entity),
         to: sandbox_email(@secondary_sale, email),
         cc: @secondary_sale.entity.entity_setting.cc,
         subject: "Secondary Sale: #{@secondary_sale.name} allocation complete.")
  end

  def notify_spa_offers
    @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
    email = User.find(params[:user_id]).email

    Rails.logger.debug { "notify_spa_offers: Sending mail to #{email}" }

    mail(from: from_email(@secondary_sale.entity),
         to: sandbox_email(@secondary_sale, email),
         cc: @secondary_sale.entity.entity_setting.cc,
         subject: "Secondary Sale: #{@secondary_sale.name}, please accept uploaded SPA.")
  end

  def notify_spa_interests
    @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
    email = User.find(params[:user_id]).email

    Rails.logger.debug { "notify_spa_interests: Sending mail to #{email}" }

    mail(from: from_email(@secondary_sale.entity),
         to: sandbox_email(@secondary_sale, email),
         cc: @secondary_sale.entity.entity_setting.cc,
         subject: "Secondary Sale: #{@secondary_sale.name}, please accept uploaded SPA.")
  end
end
