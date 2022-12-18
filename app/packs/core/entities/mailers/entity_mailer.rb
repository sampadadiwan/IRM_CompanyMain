class EntityMailer < ApplicationMailer
  def notify_created
    @entity = Entity.find params[:id]

    mail(to: ENV.fetch('SUPPORT_EMAIL', nil),
         subject: "New Entity created #{@entity.name}")
  end
end
