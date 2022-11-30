class NudgeMailer < ApplicationMailer
  def send_nudge
    @nudge = Nudge.find(params[:id])

    mail(from: from_email(@nudge.entity), to: sandbox_email(@nudge, @nudge.to),
         cc: sandbox_email(@nudge, @nudge.cc),
         bcc: sandbox_email(@nudge, @nudge.bcc).to_s,
         subject: @nudge.subject)
  end
end
