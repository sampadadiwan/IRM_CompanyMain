class ExcerciseMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def notify_excercise
    @excercise = Excercise.find params[:excercise_id]
    emails = sandbox_email(@excercise, @excercise.user.email)
    cc = @excercise.entity.entity_setting.cc

    mail(from: from_email(@excercise.entity),
         to: emails,
         cc:,
         reply_to: cc,
         subject: "New Excercise of Option by #{@excercise.user.full_name} ")
  end

  def notify_approval
    @excercise = Excercise.find params[:excercise_id]
    emails = sandbox_email(@excercise, @excercise.user.email)
    cc = @excercise.entity.entity_setting.cc
    mail(from: from_email(@excercise.entity),
         to: emails,
         cc:,
         reply_to: cc,
         subject: "Approved Excercise of Option by #{@excercise.user.full_name} ")
  end
end
