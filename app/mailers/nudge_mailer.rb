class NudgeMailer < ApplicationMailer
  def send_nudge
    @nudge = Nudge.find(params[:id])

    mail(to: sandbox_email(@nudge, @nudge.to),
         cc: sandbox_email(@nudge, @nudge.cc),
         bcc: "#{ENV['SUPPORT_EMAIL']},#{sandbox_email(@nudge, @nudge.bcc)}",
         subject: @nudge.subject)
  end
end
