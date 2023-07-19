class CapitalDistributionPaymentsMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def send_notification
    @capital_distribution_payment = CapitalDistributionPayment.find params[:capital_distribution_payment_id]
    @user = User.find params[:user_id]
    emails = sandbox_email(@capital_distribution_payment, @user.email)

    @entity = @capital_distribution_payment.entity
    cc = @entity.entity_setting.cc
    reply_to = @entity.entity_setting.cc

    if emails.present?
      mail(from: from_email(@capital_distribution_payment.entity),
           to: emails,
           reply_to:,
           cc:,
           subject: "Capital Distribution: #{@capital_distribution_payment.entity.name}")
    end
  end
end
