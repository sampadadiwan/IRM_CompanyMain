class CapitalDistributionPaymentsMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def send_notification
    @capital_distribution_payment = CapitalDistributionPayment.find params[:id]
    emails = sandbox_email(@capital_distribution_payment, @capital_distribution_payment.investor.emails_for(@capital_distribution_payment.fund))

    @entity = @capital_distribution_payment.entity
    cc = @entity.entity_setting.cc
    reply_to = @entity.entity_setting.reply_to

    if emails.present?
      mail(from: from_email(@capital_distribution_payment.entity),
           to: emails,
           reply_to:,
           cc:,
           subject: "Capital Distribution: #{@capital_distribution_payment.entity.name}")
    end
  end
end
