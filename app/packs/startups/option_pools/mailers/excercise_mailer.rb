class ExcerciseMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  def notify_excercise
    @excercise = Excercise.find params[:excercise_id]
    emails = sandbox_email(@excercise, @excercise.user.email)
    approvers = @excercise.entity.employees.joins(:roles).where("roles.name=?", :approver).pluck(:email).join(",")

    mail(from: from_email(@excercise.entity),
         to: emails,
         cc: approvers,
         subject: "New Excercise of Option by #{@excercise.user.full_name} ")
  end

  def notify_approval
    @excercise = Excercise.find params[:excercise_id]
    emails = sandbox_email(@excercise, @excercise.user.email)
    mail(from: from_email(@excercise.entity),
         to: emails,
         subject: "Approved Excercise of Option by #{@excercise.user.full_name} ")
  end
end
