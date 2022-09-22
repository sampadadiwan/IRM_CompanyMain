class InterestMailer < ApplicationMailer
  helper EmailCurrencyHelper
  helper ApplicationHelper

  def notify_interest
    @interest = Interest.find params[:interest_id]
    emails = sandbox_email(@interest, @interest.entity.employees.collect(&:email))
    mail(from: from_email(@interest.entity), to: emails,
         cc: ENV['SUPPORT_EMAIL'],
         subject: "Interest for #{@interest.secondary_sale.name} ")
  end

  def notify_shortlist
    @interest = Interest.find params[:interest_id]
    emails = sandbox_email(@interest, @interest.user.email)
    mail(from: from_email(@interest.entity), to: emails,
         cc: ENV['SUPPORT_EMAIL'],
         subject: "Interest Shortlisted for #{@interest.secondary_sale.name} ")

    msg = "Interest Shortlisted for #{@interest.secondary_sale.name} from #{@interest.secondary_sale.entity.name}. #{secondary_sale_url(@interest.secondary_sale)}"
    WhatsappSenderJob.new.perform(msg, @interest.user)
  end

  def notify_finalized
    @interest = Interest.find params[:interest_id]
    emails = sandbox_email(@interest, @interest.user.email)
    mail(from: from_email(@interest.entity), to: emails,
         cc: ENV['SUPPORT_EMAIL'],
         subject: "Interest Finalized for #{@interest.secondary_sale.name} ")

    msg = "Interest Finalized for #{@interest.secondary_sale.name} from #{@interest.secondary_sale.entity.name}. #{secondary_sale_url(@interest.secondary_sale)}"
    WhatsappSenderJob.new.perform(msg, @interest.user)
  end
end
