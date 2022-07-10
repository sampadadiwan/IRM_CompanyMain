class ExcerciseMailer < ApplicationMailer
  helper EmailCurrencyHelper
  helper ApplicationHelper

  def notify_excercise
    @excercise = Excercise.find params[:excercise_id]
    emails = @excercise.user.email
    approvers = @excercise.entity.employees.joins(:roles).where("roles.name=?", :approver).pluck(:email).join(",")

    mail(to: emails,
         cc: approvers,
         subject: "New Excercise of Option by #{@excercise.user.full_name} ")
  end

  def notify_approval
    @excercise = Excercise.find params[:excercise_id]
    emails = @excercise.user.email
    mail(to: emails,
         cc: ENV['SUPPORT_EMAIL'],
         subject: "Approved Excercise of Option by #{@excercise.user.full_name} ")
  end
end
