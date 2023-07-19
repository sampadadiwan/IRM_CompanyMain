class InterestMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def notify_interest
    @interest = Interest.find params[:interest_id]
    @user = User.find params[:user_id]
    emails = sandbox_email(@interest, @user.email)
    cc = @interest.entity.entity_setting.cc
    reply_to = cc

    mail(from: from_email(@interest.entity), to: emails, cc:, reply_to:,
         subject: "Interest received for #{@interest.secondary_sale.name} ")
  end

  def notify_shortlist
    @interest = Interest.find params[:interest_id]
    @user = User.find params[:user_id]
    emails = sandbox_email(@interest, @user.email)

    cc = @interest.entity.entity_setting.cc
    reply_to = cc

    mail(from: from_email(@interest.entity), to: emails, cc:, reply_to:,
         subject: "Interest Shortlisted for #{@interest.secondary_sale.name} ")

    msg = "Interest Shortlisted for #{@interest.secondary_sale.name} from #{@interest.secondary_sale.entity.name}. #{secondary_sale_url(@interest.secondary_sale)}"
    WhatsappSenderJob.new.perform(msg, @interest.user)
  end

  def notify_accept_spa
    @interest = Interest.find params[:interest_id]
    @user = User.find params[:user_id]
    emails = sandbox_email(@interest, @user.email)

    cc = @interest.entity.entity_setting.cc
    reply_to = cc

    mail(from: from_email(@interest.entity), to: emails, cc:, reply_to:,
         subject: "SPA confirmation received")
  end

  def notify_finalized
    @interest = Interest.find params[:interest_id]
    @user = User.find params[:user_id]
    emails = sandbox_email(@interest, @user.email)
    cc = @interest.entity.entity_setting.cc
    reply_to = cc

    mail(from: from_email(@interest.entity), to: emails, cc:, reply_to:,
         subject: "Interest Finalized for #{@interest.secondary_sale.name} ")

    msg = "Interest Finalized for #{@interest.secondary_sale.name} from #{@interest.secondary_sale.entity.name}. #{secondary_sale_url(@interest.secondary_sale)}"
    WhatsappSenderJob.new.perform(msg, @interest.user)
  end
end
