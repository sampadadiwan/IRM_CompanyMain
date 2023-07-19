class CapitalRemittancesMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def send_notification
    @capital_remittance = CapitalRemittance.find params[:capital_remittance_id]
    @user = User.find(params[:user_id])

    emails = sandbox_email(@capital_remittance, @user.email)

    @entity = @capital_remittance.entity
    cc = @entity.entity_setting.cc

    reply_to = cc

    # Check for attachments
    @capital_remittance.documents.generated.each do |doc|
      attachments["#{doc.name}.pdf"] = doc.file.read
    end

    if emails.present?
      mail(from: from_email(@capital_remittance.entity),
           to: emails,
           reply_to:,
           cc:,
           subject: "Capital Call: #{@capital_remittance.entity.name}")
    end

    # inv_advisors = investor.investor_advisors(@capital_remittance.fund)
    # inv_advisors.each do |user|
    #   CapitalRemittancesWhatsappNotifier.perform_later(user, @capital_remittance.id)
    # end

    Chewy.strategy(:sidekiq) do
      @capital_remittance.notification_sent = true
      @capital_remittance.save
    end
  end

  def notify_capital_remittance
    @capital_remittance = CapitalRemittance.find(params[:capital_remittance_id])
    @user = User.find(params[:user_id])

    emails = sandbox_email(@capital_remittance, @user.email)

    @entity = @capital_remittance.entity
    cc = @entity.entity_setting.cc
    reply_to = cc

    if emails.present?
      mail(from: from_email(@capital_remittance.entity),
           to: emails, reply_to:, cc:,
           subject: "New Capital Call by #{@capital_remittance.entity.name} : #{@capital_remittance.capital_call.name}")
    end
  end

  def reminder_capital_remittance
    @capital_remittance = CapitalRemittance.find(params[:capital_remittance_id])
    @user = User.find(params[:user_id])

    emails = sandbox_email(@capital_remittance, @user.email)

    @entity = @capital_remittance.entity
    cc = @entity.entity_setting.cc
    reply_to = cc

    if emails.present?
      mail(from: from_email(@capital_remittance.entity),
           to: emails, reply_to:, cc:,
           subject: "Reminder: Capital Call by #{@capital_remittance.entity.name} : #{@capital_remittance.capital_call.name}")
    end
  end

  def payment_received
    @capital_remittance = CapitalRemittance.find(params[:id])

    # Get all emails of investors who have pending remittances
    investor = @capital_remittance.investor
    investor_emails = sandbox_email(@capital_remittance, investor.emails_for(@capital_remittance.fund))

    @entity = @capital_remittance.entity
    cc = @entity.entity_setting.cc
    reply_to = cc

    if investor_emails.present?
      mail(from: from_email(@capital_remittance.entity),
           to: investor_emails, reply_to:, cc:,
           subject: "Payment Received. #{@capital_remittance.entity.name} : #{@capital_remittance.capital_call.name}")
    end

    # inv_advisors = investor.investor_advisors(@capital_remittance.fund)
    # inv_advisors.each do |user|
    #   CapitalRemittancesWhatsappNotifier.perform_later(user, @capital_remittance.id, ENV.fetch('CAPITAL_REMITTANCE_PAYMENT_TEMPLATE'))
    # end
  end
end
