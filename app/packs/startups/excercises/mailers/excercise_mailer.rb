class ExcerciseMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def notify_excercise
    @excercise = Excercise.find params[:excercise_id]
    @user = User.find params[:user_id]
    emails = sandbox_email(@excercise, @user.email)
    cc = @excercise.entity.entity_setting.cc

    mail(from: from_email(@excercise.entity),
         to: emails,
         cc:,
         reply_to: cc,
         subject: "New Exercise of Option by #{@excercise.user.full_name} ")
  end

  def notify_approval
    @excercise = Excercise.find params[:excercise_id]
    @user = User.find params[:user_id]
    emails = sandbox_email(@excercise, @user.email)
    cc = @excercise.entity.entity_setting.cc
    mail(from: from_email(@excercise.entity),
         to: emails,
         cc:,
         reply_to: cc,
         subject: "Approved Exercise of Option by #{@excercise.user.full_name} ")
  end

  def notify_cashless_excercise
    @excercise = Excercise.find params[:excercise_id]
    @user = User.find params[:user_id]
    emails = sandbox_email(@excercise, @user.email)
    cc = @excercise.entity.entity_setting.cc
    mail(from: from_email(@excercise.entity),
         to: emails,
         cc:,
         reply_to: cc,
         subject: "New Cashless Exercise of Option by #{@excercise.user.full_name} ")
  end
end
