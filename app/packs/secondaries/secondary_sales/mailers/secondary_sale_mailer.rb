class SecondarySaleMailer < ApplicationMailer
  helper EmailCurrencyHelper
  helper ApplicationHelper

  def notify_investment_advisors
    @secondary_sale = SecondarySale.find(params[:id])

    # Should we send emails to all advisors ? Or all second
    sale_emails = User.joins(:entity).where('entities.entity_type in (?) or users.sale_notification=?',
                                            ["Investment Advisor", "Family Office"], true).collect(&:email)

    mail(from: from_email(@secondary_sale.entity), to: ENV['SUPPORT_EMAIL'],
         bcc: sandbox_email(@secondary_sale, sale_emails.join(',')),
         subject: "New Secondary Sale: #{@secondary_sale.name} by #{@secondary_sale.entity.name}")
  end

  def notify_open_for_interests
    @secondary_sale = SecondarySale.find(params[:id])

    # Get all emails of investors & holding company employees
    all_emails = @secondary_sale.investor_users("Buyer").collect(&:email).flatten +
                 @secondary_sale.employee_users("Buyer").collect(&:emails).flatten

    Rails.logger.debug { "notify_open_for_interests: sending mail to #{all_emails}" }
    mail(from: from_email(@secondary_sale.entity), to: ENV['SUPPORT_EMAIL'],
         bcc: sandbox_email(@secondary_sale, all_emails.join(',')),
         subject: "Secondary Sale: #{@secondary_sale.name} by #{@secondary_sale.entity.name}, open for interests")
  end

  def notify_closing_interests
    @secondary_sale = SecondarySale.find(params[:id])

    # Get all emails of investors & holding company employees
    all_emails = @secondary_sale.investor_users("Buyer").collect(&:email).flatten +
                 @secondary_sale.employee_users("Buyer").collect(&:email).flatten

    Rails.logger.debug { "notify_closing_interests: sending mail to #{all_emails}" }

    mail(from: from_email(@secondary_sale.entity), to: ENV['SUPPORT_EMAIL'],
         bcc: sandbox_email(@secondary_sale, all_emails.join(',')),
         subject: "Secondary Sale: #{@secondary_sale.name} by #{@secondary_sale.entity.name}, reminder to enter your interest")
  end

  def notify_open_for_offers
    @secondary_sale = SecondarySale.find(params[:id])
    list = params[:list]

    if list

      Rails.logger.debug { "notify_open_for_offers: Sending mail to #{list} in bcc" }

      mail(from: from_email(@secondary_sale.entity), to: ENV['SUPPORT_EMAIL'],
           bcc: sandbox_email(@secondary_sale, list.join(',')),
           subject: "Secondary Sale: #{@secondary_sale.name} by #{@secondary_sale.entity.name}, open for offers")

    end
  end

  def notify_closing_offers
    @secondary_sale = SecondarySale.find(params[:id])

    list = params[:list]

    if list
      Rails.logger.debug { "notify_closing_offers: Sending mail to #{list} in bcc" }

      mail(from: from_email(@secondary_sale.entity), to: ENV['SUPPORT_EMAIL'],
           bcc: sandbox_email(@secondary_sale, open_for_offers_emails.join(',')),
           subject: "Secondary Sale: #{@secondary_sale.name} by #{@secondary_sale.entity.name}, reminder to enter your offer")
    end
  end

  def notify_allocation_offers
    @secondary_sale = SecondarySale.find(params[:id])

    list = params[:list]

    if list
      Rails.logger.debug { "notify_closing_offers: Sending mail to #{list} in bcc" }

      mail(from: from_email(@secondary_sale.entity), to: ENV['SUPPORT_EMAIL'],
           bcc: sandbox_email(@secondary_sale, list.join(',')),
           subject: "Secondary Sale: #{@secondary_sale.name} allocation complete.")
    end
  end

  def notify_allocation_interests
    @secondary_sale = SecondarySale.find(params[:id])

    interests_emails = @secondary_sale.interests.short_listed.collect(&:notification_emails).flatten

    all_emails = interests_emails
    mail(from: from_email(@secondary_sale.entity), to: ENV['SUPPORT_EMAIL'],
         bcc: sandbox_email(@secondary_sale, all_emails.join(',')),
         subject: "Secondary Sale: #{@secondary_sale.name} allocation complete.")
  end

  def notify_spa_offers
    @secondary_sale = SecondarySale.find(params[:id])
    list = params[:list]

    if list

      Rails.logger.debug { "notify_spa_offers: Sending mail to #{list} in bcc" }

      mail(from: from_email(@secondary_sale.entity), to: ENV['SUPPORT_EMAIL'],
           bcc: sandbox_email(@secondary_sale, list.join(',')),
           subject: "Secondary Sale: #{@secondary_sale.name}, please accept uploaded SPA.")

    end
  end

  def notify_spa_interests
    @secondary_sale = SecondarySale.find(params[:id])
    all_emails = params[:list]

    Rails.logger.debug { "notify_spa_interests: Sending mail to #{all_emails} in bcc" }

    mail(from: from_email(@secondary_sale.entity), to: ENV['SUPPORT_EMAIL'],
         bcc: sandbox_email(@secondary_sale, all_emails.join(',')),
         subject: "Secondary Sale: #{@secondary_sale.name}, please accept uploaded SPA.")
  end
end
