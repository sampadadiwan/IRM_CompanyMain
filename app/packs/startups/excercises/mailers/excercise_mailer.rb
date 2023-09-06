class ExcerciseMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def notify_excercise
    @excercise = Excercise.find params[:excercise_id]
    send_mail(subject: "New Exercise of Option by #{@excercise.user.full_name} ")
  end

  def notify_approval
    @excercise = Excercise.find params[:excercise_id]
    send_mail(subject: "Approved Exercise of Option by #{@excercise.user.full_name} ")
  end

  def notify_cashless_excercise
    @excercise = Excercise.find params[:excercise_id]
    send_mail(subject: "New Cashless Exercise of Option by #{@excercise.user.full_name} ")
  end
end
